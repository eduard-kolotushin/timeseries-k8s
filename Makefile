CHART := charts/timeseries
GRAFANA_IMAGE := ghcr.io/eduard-kolotushin/timeseries-grafana:0.1.0
BASELINES_IMAGE := ghcr.io/eduard-kolotushin/timeseries-baselines:0.1.0
HELM ?= helm
HELM_REPO_CONFIG := $(CURDIR)/.helm/repositories.yaml
HELM_REPO_CACHE := $(CURDIR)/.helm/cache
HELM_GRAFANA_REPO := https://grafana-community.github.io/helm-charts
# cmd.exe has no /dev/null (make uses cmd as its shell when PATH has no sh.exe, i.e. in a
# PowerShell session) and sh has no NUL; both name a null device on Windows.
NULLDEV := $(if $(filter Windows_NT,$(OS)),NUL,/dev/null)

.PHONY: all help lint helm-deps docker-grafana docker-baselines

all: lint

help:
	@echo "make lint             helm dependency update, lint, template"
	@echo "make docker-grafana   build Grafana-with-plugin image"
	@echo "make docker-baselines build worker image"

# Isolated Grafana helm repo. A leftover global repo (e.g. Bitnami) with a missing
# index file makes Helm 4 fail even with --skip-refresh.
helm-deps:
	$(HELM) --repository-config "$(HELM_REPO_CONFIG)" --repository-cache "$(HELM_REPO_CACHE)" repo add grafana $(HELM_GRAFANA_REPO) --force-update
	$(HELM) --repository-config "$(HELM_REPO_CONFIG)" --repository-cache "$(HELM_REPO_CACHE)" dependency update $(CHART)

lint: helm-deps
	helm lint $(CHART) -f ci/values.yaml
	helm template test $(CHART) -f ci/values.yaml >$(NULLDEV)

docker-grafana:
	docker build -f docker/grafana/Dockerfile -t $(GRAFANA_IMAGE) docker/grafana

docker-baselines:
	docker build -f docker/baselines/Dockerfile -t $(BASELINES_IMAGE) docker/baselines
