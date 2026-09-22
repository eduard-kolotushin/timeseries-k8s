# Project intentions

## Goal

Deploy the forecast Grafana plugin and the minute-of-week baselines worker on an existing Kubernetes cluster. This repo owns container images and Helm. It does not own plugin source, worker source, Series math, or a local Compose/Helm sandbox.

## Locked choices

| Decision | Choice |
| --- | --- |
| Repo | sibling `timeseries-k8s` |
| Chart | `charts/timeseries` (umbrella) |
| Grafana | custom OSS `grafana/grafana:13.1.0` image with the unsigned forecast plugin baked in |
| Worker | own Deployment + headless Service (replicas independent of Grafana); image of `timeseries-baselines` `cmd/baselines` |
| Kafka / Druid | cluster-owned; URLs via Helm values (sandbox Helm path can install them) |
| Prometheus / OpenSearch / Postgres | cluster-owned; optional datasource URLs via Helm values (empty default). This chart does not run those servers |
| Images | linux/amd64; GHCR `ghcr.io/eduard-kolotushin/timeseries-grafana` and `…/timeseries-baselines` |
| Plugin load | `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS` (not development mode, not grafana.com signing) |
| Auth | Grafana Helm admin secret; no anonymous Admin (sandbox values may override) |
| Source pins | Dockerfiles clone sibling git (plugin `861d25d3174b80cef5cc8da1f953091b10a2d476`, worker `7ec489faafeb85971dd5f5c247aaf0bc37c63913`) |

Both pins are `ARG` defaults in `docker/grafana/Dockerfile` and `docker/baselines/Dockerfile`, and
they are bumped in the same pass as the sibling change they carry; `make check-pins` (in CI) fails when
a pin is neither the sibling head nor an ancestor of it.

## v1 must-have

- Grafana with `eduardkolotushin-forecast-app` / `eduardkolotushin-forecast-panel` / `eduardkolotushin-forecast-datasource` and `grafadruid-druid-datasource` in the image
- Bake `grafana-opensearch-datasource` next to Druid (Prometheus and Postgres are Grafana core)
- Plugins live under `/opt/grafana-plugins` so a Grafana PVC does not hide them
- Optional Druid datasource URL in values
- Optional `prometheusUrl` / `opensearchUrl` / `postgres` connection values (empty default), same pattern as `druidUrl`. When `postgres.url` is set, those values also provision the forecast app snapshot store and Forecast datasource jsonData (pgx, schema `forecast`); this chart still does not run a Postgres server
- Enable the forecast app via provisioning
- Optional baselines worker Deployment (env `DRUID_*` / `KAFKA_*` as in `timeseries-baselines`)
- Worker replicas are independent of Grafana replicas; scale the worker without touching Grafana
- Official Grafana Helm chart as a subchart (`grafana-community`)
- `helm lint` / `helm template` in CI; GHCR image publish on `v*` tags

## v2 must-have

- Scalable baselines worker: `baselines.replicas`, `SHARD_ID` (Downward API `status.podIP`) and `SHARD_DNS` (headless Service) so peers find each other with no coordinator; `SHARD_PEERS` stays available for explicit VMs
- Duplicate-tolerant ingestion: the Kafka key is `metric_hash|metric_ts`, and a repeated point must be collapsed idempotently by the sink (Druid `doubleMax` with `queryGranularity: minute` and `rollup: true`, not `doubleSum`). Restarts, handover, and stale peer lists all republish points
- Worker replicas independent of Grafana replicas; the worker must render and run with `grafana.enabled=false`
- No worker probes and no HTTP endpoint; the worker serves no HTTP

## v3 must-have

- Bounded Druid access from the worker: `baselines.druidMaxRange` (a single SQL request may not span more than this), `druidMaxRps`, `trainConcurrency`, `hashScanTtl`, `workerTtl`, `defaultRetrainCron` reach the pod as `DRUID_MAX_RANGE`, `DRUID_MAX_RPS`, `TRAIN_CONCURRENCY`, `HASH_SCAN_TTL`, `WORKER_TTL`, `DEFAULT_RETRAIN_CRON`. `workerTtl` is empty by default — the worker then derives `max(30s, 2*INTERVAL)`, so the chart cannot pin a TTL that its own `interval` default would contradict. Publishing no longer reads Druid; the scan is cached for `HASH_SCAN_TTL` and series reads happen only inside a retrain window
- Snapshot persistence from the existing `postgres.*` values: the worker ConfigMap renders `BASELINE_STORE_HOST/PORT/DATABASE/USER/PASSWORD/SSLMODE` with the same host/port splitting `forecast-store-env.yaml` uses, so one Postgres serves the plugin's `forecast` schema and the worker's `baselines` schema. Empty `postgres.url` renders the keys empty, exactly like the forecast-store ConfigMap, and the worker keeps its per-tick fit path. `baselines.storeHost` overrides the rendered host (and optional `:port`) only — the credentials and database still come from `postgres.*` — for an install that reaches the same store by a different DNS name. `baselines.membership=store` requires a store: with neither `postgres.url` nor `storeHost` the worker rejects the configuration at startup and exits, so it is never a silent fallback to `dns`
- Fleet membership source is a value: `baselines.membership` (default `dns`) reaches the pod through the ConfigMap only, so the Deployment keeps `SHARD_ID` (pod IP) and `SHARD_DNS` (headless Service) and the verified headless path stays the chart default. `store` selects the Postgres heartbeat (`baselines.workers`) that the sandbox uses
- The plugin scheduler's own settings are provisionable: `grafana.retrainCron` → app `jsonData.retrainCron`, `grafana.pluginToken` → `secureJsonData.grafanaToken` (a Viewer service-account token for `POST /api/ds/query` when anonymous auth is off). Both are omitted when empty, so the app ConfigMap keeps its current shape by default

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

## v2 non-goals

Do not add these without first updating this document:

- Shard coordinator or leader election (ownership is rendezvous hashing over the peer set)
- A service mesh for worker traffic
- HPA tuning or autoscaling policies
- A worker HTTP endpoint (health, metrics, or admin)

## Quality bar

- Dockerfiles do not copy sibling source trees; they fetch a pinned git ref
- `baselines.druidBroker` and `baselines.kafkaBrokers` are required when the worker is enabled
- The worker runs as its own Deployment and does not require `grafana.enabled`; disable it with `baselines.enabled=false`
- GitHub Actions on `main` runs `helm lint` and `helm template`
