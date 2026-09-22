CHART := charts/timeseries
GRAFANA_IMAGE := ghcr.io/eduard-kolotushin/timeseries-grafana:0.1.0
BASELINES_IMAGE := ghcr.io/eduard-kolotushin/timeseries-baselines:0.1.0
HELM ?= helm
HELM_REPO_CONFIG := $(CURDIR)/.helm/repositories.yaml
HELM_REPO_CACHE := $(CURDIR)/.helm/cache
HELM_GRAFANA_REPO := https://grafana-community.github.io/helm-charts
# Sibling sandbox checkout. Absent in CI, where `lint` skips it; present locally, where rendering it
# catches a values combination the chart's own ci/values.yaml does not exercise.
SANDBOX_VALUES := ../timeseries-grafana-sandbox/helm/timeseries-values.yaml
GITHUB_ORG := https://github.com/eduard-kolotushin
# make uses cmd.exe as its shell when PATH has no sh.exe — the case in a PowerShell or cmd
# session — where POSIX recipes and /dev/null do not exist. Pin Git's sh.exe the way the
# sibling repos do, so every launcher runs the same recipes.
ifeq ($(OS),Windows_NT)
GIT_SH := $(if $(wildcard C:/Program\ Files/Git/bin/sh.exe),C:/Program Files/Git/bin/sh.exe,$(wildcard $(subst \,/,$(LOCALAPPDATA))/Programs/Git/bin/sh.exe))
ifneq ($(strip $(GIT_SH)),)
SHELL := $(GIT_SH)
endif
endif

.PHONY: all help lint check-pins helm-deps docker-grafana docker-baselines

all: lint

help:
	@echo "make lint             helm dependency update, lint, template (sandbox values when present)"
	@echo "make check-pins       fail when a Dockerfile git pin is stale against its sibling head"
	@echo "make docker-grafana   build Grafana-with-plugin image"
	@echo "make docker-baselines build worker image"

# Isolated Grafana helm repo. A leftover global repo (e.g. Bitnami) with a missing
# index file makes Helm 4 fail even with --skip-refresh.
helm-deps:
	$(HELM) --repository-config "$(HELM_REPO_CONFIG)" --repository-cache "$(HELM_REPO_CACHE)" repo add grafana $(HELM_GRAFANA_REPO) --force-update
	$(HELM) --repository-config "$(HELM_REPO_CONFIG)" --repository-cache "$(HELM_REPO_CACHE)" dependency update $(CHART)

lint: helm-deps
	helm lint $(CHART) -f ci/values.yaml
	helm template test $(CHART) -f ci/values.yaml >/dev/null
	@if [ -f "$(SANDBOX_VALUES)" ]; then \
		echo "lint: rendering $(SANDBOX_VALUES)"; \
		helm lint $(CHART) -f ci/values.yaml -f "$(SANDBOX_VALUES)"; \
		helm template test $(CHART) -f ci/values.yaml -f "$(SANDBOX_VALUES)" >/dev/null; \
	else \
		echo "lint: $(SANDBOX_VALUES) is not present, skipped"; \
	fi

# Each Dockerfile clones a sibling at a pinned commit, and only a full Dockerfile refresh changes
# what a released image contains. A pin that is neither that sibling's head nor an ancestor of it
# therefore ships stale code unnoticed; this is the check CI runs on every pull request.
check-pins:
	@set -e; \
	for spec in \
		"timeseries-grafana:docker/grafana/Dockerfile:PLUGIN_REF" \
		"timeseries-baselines:docker/baselines/Dockerfile:BASELINES_REF"; do \
		repo=$${spec%%:*}; rest=$${spec#*:}; file=$${rest%%:*}; var=$${rest##*:}; \
		ref=$$(sed -n "s/^ARG $${var}=//p" "$$file"); \
		if [ -z "$$ref" ]; then echo "$$file: no ARG $${var}" >&2; exit 1; fi; \
		head=$$(git ls-remote "$(GITHUB_ORG)/$$repo" HEAD | cut -f1); \
		if [ "$$ref" = "$$head" ]; then echo "$$repo: $$ref is the head"; continue; fi; \
		dir=$$(mktemp -d); \
		git -C "$$dir" init -q; \
		git -C "$$dir" remote add origin "$(GITHUB_ORG)/$$repo"; \
		git -C "$$dir" fetch -q --tags origin; \
		if git -C "$$dir" merge-base --is-ancestor "$$ref" "$$head" 2>/dev/null; then \
			echo "$$repo: $$ref is an ancestor of the head ($$head)"; \
		else \
			echo "$$repo: $$ref is neither the head ($$head) nor an ancestor of it" >&2; \
			rm -rf "$$dir"; exit 1; \
		fi; \
		rm -rf "$$dir"; \
	done

docker-grafana:
	docker build -f docker/grafana/Dockerfile -t $(GRAFANA_IMAGE) docker/grafana

docker-baselines:
	docker build -f docker/baselines/Dockerfile -t $(BASELINES_IMAGE) docker/baselines
