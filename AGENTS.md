# AGENTS.md

Operating manual for agents working in this repository.

## Project

Kubernetes images and Helm for the forecast Grafana plugin and the baselines worker. Not plugin source, not worker source, not a Compose sandbox.

- **Folder:** `timeseries-k8s`
- **Chart:** `charts/timeseries`
- **Images:** `ghcr.io/eduard-kolotushin/timeseries-grafana`, `ghcr.io/eduard-kolotushin/timeseries-baselines`

## Read first

1. [docs/INTENTIONS.md](docs/INTENTIONS.md)
2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Hard constraints

- Do not copy plugin or worker source into this repo; Dockerfiles fetch pinned sibling git refs
- Do not add Kafka, Druid, Prometheus, OpenSearch, or Postgres **servers**, TestData, or sandbox dashboards
- Stay within v1 unless `docs/INTENTIONS.md` is updated first
- linux/amd64 only
- Unsigned plugin load via `allow_loading_unsigned_plugins`, not `GF_DEFAULT_APP_MODE=development`
- Worker is a Grafana sidecar, not a separate Deployment

## v1 in scope

Grafana-with-plugin image (forecast app, overlay panel, forecast datasource + Druid + OpenSearch datasource plugins), worker image, umbrella Helm chart assuming existing Kafka/Druid and optional Prom/OS/PG URLs. `postgres` values also provision `FORECAST_STORE_*` and Forecast datasource jsonData for fitted snapshots.

## v1 out of scope

Plugin implementation, worker implementation, Compose sandbox, Prometheus/OpenSearch/Postgres servers in this chart, grafana.com signing, arm64, worker HTTP probes, Kafka/Druid in this chart.

## Workflow

- `make lint` — `make helm-deps`, `helm lint`, `helm template`
- `make docker-grafana` / `make docker-baselines` — local image builds
- Bump Dockerfile `PLUGIN_REF` / `BASELINES_REF` when siblings change
- Full local stack (Kafka + Druid + Prom/OS/PG + this chart): sibling `timeseries-grafana-sandbox` `make helm-up`
- GitHub Actions on `main`: helm lint/template; on `v*` tags: push both images to GHCR
