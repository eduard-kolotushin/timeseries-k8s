# AGENTS.md

Operating manual for agents working in this repository.

## Project

Kubernetes images and Helm for the forecast Grafana plugin and the baselines worker. Not plugin source, not worker source, not a Compose sandbox.

- **Folder:** `timeseries-k8s`
- **Chart:** `charts/timeseries`
- **Images:** `ghcr.io/eduard-kolotushin/timeseries-grafana`, `ghcr.io/eduard-kolotushin/timeseries-baselines`, `ghcr.io/eduard-kolotushin/timeseries-forecast-compute`

## Read first

1. [docs/INTENTIONS.md](docs/INTENTIONS.md)
2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Hard constraints

- Do not copy plugin, worker, or compute source into this repo; Dockerfiles fetch pinned sibling git refs
- Do not add Kafka, Druid, Prometheus, OpenSearch, or Postgres **servers**, TestData, or sandbox dashboards
- Stay within v1/v2/v3/v4/v5 unless `docs/INTENTIONS.md` is updated first
- linux/amd64 only
- Unsigned plugin load via `allow_loading_unsigned_plugins`, not `GF_DEFAULT_APP_MODE=development`
- Worker is a Deployment of its own; its replicas are independent of Grafana replicas
- The compute service is a Deployment of its own too (`compute.enabled`, default off) and is switched on through the app provisioning ConfigMap, never through `grafana.env`: Dockerfiles fetch the siblings' `cmd/compute`, this repo never implements it

## v1 in scope

Grafana-with-plugin image (forecast app, overlay panel, forecast datasource + Druid + OpenSearch datasource plugins), worker image, umbrella Helm chart assuming existing Kafka/Druid and optional Prom/OS/PG URLs. `postgres` values also provision `FORECAST_STORE_*` and Forecast datasource jsonData for fitted snapshots.

## v2 in scope

Scalable worker Deployment + headless Service (`baselines.replicas`, `SHARD_ID`/`SHARD_DNS`, no coordinator), duplicate-tolerant ingestion (`doubleMax`, minute rollup), worker replicas independent of Grafana replicas.

## v3 in scope

Bounded worker Druid access (`baselines.druidMaxRange` / `druidMaxRps` / `trainConcurrency` / `hashScanTtl` / `workerTtl` / `defaultRetrainCron`), snapshot persistence and fleet membership from the same `postgres.*` values (`baselines.storeHost`, `baselines.membership`), and the plugin scheduler's own values (`grafana.retrainCron`, `grafana.pluginToken`).

## v4 in scope

The plugin's standalone compute service (v16): `docker/compute/Dockerfile` + `make docker-compute` + the `v*` tag image job + `check-pins`, and `compute.*` values rendering a Deployment (`<release>-forecast-compute`, `compute.replicas`), a ported ClusterIP Service on 8080, an env ConfigMap (`FORECAST_COMPUTE_LISTEN`, a Grafana URL defaulting to `http://<release>-grafana:80`, optional inflight/retrain/TTL knobs), a `<release>-compute-credentials` Secret (`compute.token` required) as the service-side copy of the token, and the shared store ConfigMap/Secret. `compute.enabled` also adds `computeUrl`/`computeToken` to the app provisioning ConfigMap — the only switch that reaches the plugin process — which then forwards `POST /forecast` and runs no retrain ticker. No credential is rendered into a ConfigMap: the app's and the datasources' `secureJsonData` values are `$VAR` references Grafana expands from its process env, which the Grafana pod takes from the `<release>-store-credentials` and `<release>-plugin-credentials` (`FORECAST_GRAFANA_TOKEN` / `FORECAST_COMPUTE_TOKEN`) Secrets, and a CI render checks that with probe values. Default off; a compute change needs `grafana.configRevision` bumped to roll Grafana.

## v5 in scope

Vault PKI mTLS for the compute hop (`vault.*` values, `https` computeUrl, Vault env in ConfigMaps, credentials only in Secrets, CI render checks). v21 adds selectable Vault API client-certificate mTLS (`vault.mtls` / `clientCertFile` / `clientKeyFile`, plus `compute.extraVolumes`/`extraVolumeMounts`; the operator mounts the file pair, the chart only renders paths and env/jsonData).

## v1/v2/v3/v4/v5 out of scope

Plugin implementation, worker implementation, compute-service implementation, Compose sandbox, Prometheus/OpenSearch/Postgres servers in this chart, grafana.com signing, arm64, worker HTTP probes (the compute service's coarse `/healthz` is the named exception), Kafka/Druid in this chart, worker leader election or coordinator, service mesh, HPA tuning, worker HTTP endpoint, a compute Service exposed outside the cluster, and a compute switch through `grafana.env` (provisioning only — Grafana does not forward host env to plugin processes).

## Workflow

- `make lint` — `make helm-deps`, `helm lint`, `helm template` (also renders `ci/values.yaml`, which enables `compute`)
- `make docker-grafana` / `make docker-baselines` / `make docker-compute` — local image builds
- Scale the worker: `kubectl -n <ns> scale deployment/<release>-baselines --replicas=N`; scale fitting: `kubectl -n <ns> scale deployment/<release>-forecast-compute --replicas=N`
- Bump Dockerfile `PLUGIN_REF` (both `docker/grafana/` and `docker/compute/`) / `BASELINES_REF` when siblings change; `make check-pins` covers all three
- Full local stack (Kafka + Druid + Prom/OS/PG + this chart): sibling `timeseries-grafana-sandbox` `make helm-up`
- GitHub Actions on `main`: helm lint/template + the compute render checks + the no-credential-in-a-ConfigMap render + `make check-pins`; on `v*` tags: push all three images to GHCR (the image job needs the helm job)
