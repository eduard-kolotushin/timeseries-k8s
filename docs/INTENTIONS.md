# Project intentions

## Goal

Deploy the forecast Grafana plugin and the minute-of-week baselines worker on an existing Kubernetes cluster. This repo owns container images and Helm. It does not own plugin source, worker source, Series math, or a local Compose/Helm sandbox.

## Locked choices

| Decision | Choice |
| --- | --- |
| Repo | sibling `timeseries-k8s` |
| Chart | `charts/timeseries` (umbrella) |
| Grafana | custom OSS `grafana/grafana:13.1.0` image with the unsigned forecast plugin baked in |
| Worker | sidecar on the Grafana pod; image of `timeseries-baselines` `cmd/baselines` |
| Kafka / Druid | cluster-owned; URLs via Helm values (sandbox Helm path can install them) |
| Prometheus / OpenSearch / Postgres | cluster-owned; optional datasource URLs via Helm values (empty default). This chart does not run those servers |
| Images | linux/amd64; GHCR `ghcr.io/eduard-kolotushin/timeseries-grafana` and `…/timeseries-baselines` |
| Plugin load | `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS` (not development mode, not grafana.com signing) |
| Auth | Grafana Helm admin secret; no anonymous Admin (sandbox values may override) |
| Source pins | Dockerfiles clone sibling git (plugin `0231c2d5ea22cdff4e42558ca2509ebe8175ddc6`, worker `ee71550923faceb4d019a56cd2be065f607cdf6f`) |

## v1 must-have

- Grafana with `eduardkolotushin-forecast-app` / `eduardkolotushin-forecast-panel` and `grafadruid-druid-datasource` in the image
- Bake `grafana-opensearch-datasource` next to Druid (Prometheus and Postgres are Grafana core)
- Plugins live under `/opt/grafana-plugins` so a Grafana PVC does not hide them
- Optional Druid datasource URL in values
- Optional `prometheusUrl` / `opensearchUrl` / `postgres` connection values (empty default), same pattern as `druidUrl`
- Enable the forecast app via provisioning
- Optional baselines worker **sidecar** in the Grafana pod (env `DRUID_*` / `KAFKA_*` as in `timeseries-baselines`)
- One Grafana replica (therefore one worker); do not scale out
- Official Grafana Helm chart as a subchart (`grafana-community`)
- `helm lint` / `helm template` in CI; GHCR image publish on `v*` tags

## v1 non-goals

Do not add these without first updating this document:

- Kafka, ZooKeeper, or Druid in this chart
- Prometheus, OpenSearch, or Postgres **servers** in this chart
- Wikipedia ingest, TestData, or sandbox demo dashboards
- Prometheus server or alerting in this chart
- Grafana.com plugin signing
- Plugin or worker source (siblings `timeseries-grafana` and `timeseries-baselines`)
- arm64 images
- Worker HTTP `/healthz`
- Folding the ticker into Grafana
- A separate worker Deployment

## Quality bar

- Dockerfiles do not copy sibling source trees; they fetch a pinned git ref
- `baselines.druidBroker` and `baselines.kafkaBrokers` are required when the worker is enabled
- Worker sidecar requires Grafana (`grafana.enabled`); disable with `baselines.enabled=false` and empty `grafana.extraContainers`
- GitHub Actions on `main` runs `helm lint` and `helm template`
