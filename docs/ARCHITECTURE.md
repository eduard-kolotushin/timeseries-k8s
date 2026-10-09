# Architecture

## Layout

| Path | Responsibility |
| --- | --- |
| `docker/grafana/Dockerfile` | Build plugin `dist/` from pinned `timeseries-grafana`, copy into Grafana 13.1.0 OSS |
| `docker/baselines/Dockerfile` | Static `cmd/baselines` from pinned `timeseries-baselines` |
| `docker/compute/Dockerfile` | Static `cmd/compute` (`gpx_forecast_compute`) from pinned `timeseries-grafana` |
| `charts/timeseries` | Umbrella Helm chart |
| `charts/timeseries/charts/` | Grafana community subchart (fetched, gitignored) |
| `ci/values.yaml` | Dummy broker URLs and an enabled `compute` block for `helm lint` / `helm template` |

Plugin and worker git pins are `ARG` defaults in the Dockerfiles (`PLUGIN_REF=da363f4a552b20b70356b2c1abfeecfd573875e6` in both `docker/grafana/` and `docker/compute/`, `BASELINES_REF=a886d144af088851f90eb6d5e519a843ba3b61fe`). They are bumped in the same pass as the sibling change they carry, and CI's `make check-pins` fails when a pin is neither the sibling head nor an ancestor of it.

## Cluster data flow

Grafana (custom image) queries existing datasources and runs `POST /api/plugins/eduardkolotushin-forecast-app/resources/forecast` in-process. With `compute.enabled` the app is provisioned with `computeUrl` pointing at the compute Service, so that handler forwards the request there instead of fitting and the plugin process runs no retrain ticker; the compute Deployment owns fitting, the ticker and retention, fetches its frames from Grafana's own `/api/ds/query` (`FORECAST_GRAFANA_URL` defaults to `http://<release>-grafana:80`, since the plugin's loopback default only reaches Grafana from inside a Grafana pod) and shares the same `postgres.*` store. Alerting `QueryData` and the Retrain schedules page stay in the Grafana process, so they keep working while the compute Deployment is down; a panel fit then answers `502` rather than fitting inside Grafana. `compute.replicas` scales fitting independently, and the claim queue keeps each due row to one replica.

The baselines worker runs in its own Deployment, independent of Grafana. It publishes from a stored snapshot, trains on a cron through a claim queue that any replica can take, and divides ownership of the metric hashes across `baselines.replicas` pods by rendezvous hashing, so no coordinator is needed. Druid access is bounded: every scan and series read is sliced to `baselines.druidMaxRange` and rate-limited, the hash scan is cached for `hashScanTtl`, and publishing costs no Druid requests at all. Its peer set comes from `baselines.membership`: `dns` (chart default) resolves the headless Service, `store` reads the `baselines.workers` heartbeat table in the `postgres.*` instance (`baselines.storeHost` overrides only the rendered store host/port; the DSN's credentials and database stay `postgres.*`).

Kafka, Druid, Prometheus, OpenSearch, and Postgres are not in this chart. Optional datasource URLs (`druidUrl`, `prometheusUrl`, `opensearchUrl`, `postgres`) provision Grafana datasources when set. The same `postgres` values provision `FORECAST_STORE_*` (Grafana container), app jsonData, Forecast datasource jsonData, and the worker's `BASELINE_STORE_*` for fitted snapshots and the retrain queue. Grafana 12.4+ does not forward host `FORECAST_STORE_*` into plugin processes. The sibling sandbox can install the servers with `make helm-up`.

Grafana's plugin backend retrains stored panel snapshots on a cron (`grafana.retrainCron` → app `jsonData.retrainCron`), claiming due rows in `forecast.retrain` and fetching frames from its own `POST /api/ds/query`. With anonymous auth off that call needs a token: `grafana.pluginToken` is provisioned as `secureJsonData.grafanaToken`, the same path as `postgres.password`.

## Grafana image

1. Node 22: `npm ci` + `npm run build` in the pinned plugin repo (webpack `dist/`).
2. Go 1.26: `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dist/gpx_forecast_linux_amd64 ./pkg` and copy that binary into `dist/forecast-datasource/`.
3. `grafana cli plugins install grafadruid-druid-datasource 1.8.0` and `… plugins install grafana-opensearch-datasource 2.34.4` (pinned; the sandbox Compose file installs the same versions via `GF_PLUGINS_PREINSTALL` (`id@version`), because Grafana 13 ignores the `@version` suffix of the legacy `GF_INSTALL_PLUGINS` and answers 404 for it).
4. Copy forecast `dist/` and the third-party plugins into `/opt/grafana-plugins`.
5. `GF_PATHS_PLUGINS=/opt/grafana-plugins` and `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS` for the forecast app, overlay panel, and forecast datasource IDs.
6. Run as uid `472`.

Prometheus and Postgres are Grafana core; they are not installed via `grafana cli`.

The Grafana Helm subchart must set `grafana.ini.paths.plugins` to `/opt/grafana-plugins`. A PVC at `/var/lib/grafana` then keeps sqlite/dashboards without overlaying the baked plugins.

## Worker image

`CGO_ENABLED=0` build of `./cmd/baselines`, distroless static nonroot, entrypoint `/baselines`. Config is process env (see `timeseries-baselines` ARCHITECTURE). No HTTP port, hence no probes and no Service port; Kubernetes restarts the worker pod if the process exits.

## Compute image

`CGO_ENABLED=0` build of `./cmd/compute` from the pinned `timeseries-grafana` ref, distroless static nonroot, entrypoint `/gpx_forecast_compute`. Configuration is process env only (`FORECAST_COMPUTE_LISTEN`, `FORECAST_COMPUTE_TOKEN`, `FORECAST_STORE_*`, `FORECAST_GRAFANA_*`, the `FORECAST_RETRAIN_*` / `FORECAST_SNAPSHOT_TTL` / `FORECAST_MAX_INFLIGHT` knobs); it has no grafana.ini and no jsonData in reach, and it ignores `FORECAST_COMPUTE_URL`. The pod exposes one HTTP port (8080) that only the plugin's forwarded `POST /forecast` uses, so the Service is ClusterIP and probes are TCP.

## Helm

- Subchart `grafana` from `https://grafana-community.github.io/helm-charts`, condition `grafana.enabled`.
- Parent templates: forecast-app ConfigMap, forecast datasource ConfigMap, forecast-store env ConfigMap (`FORECAST_STORE_*` minus the password, Grafana `envFromConfigMaps`), a `<release>-store-credentials` Secret (`FORECAST_STORE_PASSWORD` / `BASELINE_STORE_PASSWORD`, Grafana `envFromSecrets` and the worker's and compute's `envFrom secretRef`), optional Druid / Prometheus / OpenSearch / Postgres datasource ConfigMaps (`optional: true` mounts), baselines env ConfigMap, and (with `compute.enabled`) a compute env ConfigMap, a `<release>-compute-credentials` Secret and the compute Deployment + ported Service.
- The compute Deployment `{{ .Release.Name }}-forecast-compute` (`compute.replicas`, default off) runs the pinned `cmd/compute` image with no arguments: `FORECAST_COMPUTE_LISTEN`, `FORECAST_GRAFANA_URL`, the optional inflight/retrain/TTL knobs, the shared store ConfigMap/Secret and its own credentials Secret. Its Service is the only port-exposing parent template (ClusterIP 8080); its probes are TCP, because `/healthz` needs the shared token and a probe cannot carry one. The pod template carries `checksum/compute-env`, `checksum/store-credentials` and `checksum/compute-credentials`.
- `compute.enabled` also renders `computeUrl`/`computeToken` into the app ConfigMap — the only switch that reaches the plugin process, since the Grafana subchart's value scope cannot see `compute.*` and Grafana does not forward host env to plugin processes. Like a store change, a compute change therefore needs `grafana.configRevision` bumped to roll the Grafana pod.
- `postgres.url` and `baselines.storeHost` accept `host`, `host:port` and a `scheme://[user[:pass]@]host[:port][/db]` DSN (one helper renders both); a value that yields no host fails the render. A DSN contributes host and port only — credentials and database stay `postgres.database`/`user`/`password`. `postgres.sslMode` (default `disable`) is the sslmode every render uses.
- Every datasource provisioning file is rendered whenever Grafana is on, even with no URL for it: the subchart's `extraConfigmapMounts` entries are unconditional, and an `optional: true` mount of a ConfigMap that does not exist becomes a *directory* at the file path, which makes Grafana 13 refuse to start (`read /etc/grafana/provisioning/datasources/druid.yaml: is a directory` — measured on an install with `druidUrl`/`prometheusUrl`/`opensearchUrl` empty). With no URL the file carries `datasources: []`, so the datasource simply is not provisioned. CI renders a URL-less install and requires all four files.
- Grafana reads provisioning only at startup and every provisioning mount uses `subPath`, so a values change needs a rollout. The Grafana subchart templates `env`/`envFrom*`/mount fields in its own value scope (which cannot see this chart's `postgres` block) and does not template `podAnnotations`; the Deployment therefore carries a `FORECAST_CONFIG_CHECKSUM` env built from `grafana.retrainCron`/`pluginToken`/`configRevision`, and a store-only change is rolled with `--set grafana.configRevision=<anything>`. The worker Deployment carries `checksum/baselines-env` and `checksum/store-credentials`.
- Grafana's container gets default requests/limits (2Gi memory, which also sets `GOMEMLIMIT`); the plugin's fits run in that process.
- An image tag is an override, not a delivery channel: `pullPolicy: IfNotPresent` keeps a cached tag on a node, so a rebuilt image must be published under a new immutable tag (a commit sha or a `vX.Y.Z` release) and set on the release.
- The baselines env ConfigMap carries the existing `DRUID_*` / `KAFKA_*` / `LOOKBACK` keys plus the bounds (`DRUID_MAX_RANGE`, `DRUID_MAX_RPS`, `TRAIN_CONCURRENCY`, `HASH_SCAN_TTL`, `WORKER_TTL`, `DEFAULT_RETRAIN_CRON`, `SHARD_MEMBERSHIP`, `LOG_LEVEL`, `DRUID_TIMEOUT`, `DRUID_RETRIES`, `DRUID_MAX_INFLIGHT`, `DRUID_AUTH_HEADER`, `DRUID_AUTH_VALUE`, `SCAN_RANGE`, `SNAPSHOT_CACHE_TTL`, `RETRAIN_RETRY`, `RETRAIN_LEASE`, `RETRAIN_RETRY_MAX` — the last eleven only when set) and the `BASELINE_STORE_*` block split from `postgres.url` (minus the password, which the Secret carries), so the worker needs no extra mount to reach the snapshot store.
- `SHARD_MEMBERSHIP` lives in the ConfigMap only (`baselines.membership`, default `dns`); the Deployment keeps `SHARD_ID` and `SHARD_DNS`, so setting a different membership source never deletes the headless-Service path from the pod spec.
- Worker Deployment `{{ .Release.Name }}-baselines` (`baselines.replicas`) plus a headless Service `-baselines-headless` with no ports; its A records are the pod IPs that `SHARD_DNS` resolves, and `SHARD_ID` is `status.podIP` from the Downward API.
- The worker `envFrom`s the `baselines-env` ConfigMap and shares no lifecycle with Grafana: it renders with `grafana.enabled=false`, and its replicas are scaled independently.
- Adding or removing a replica moves about `1/N` of the metric hashes; duplicate points are collapsed by the sink (`doubleMax`, minute rollup).
