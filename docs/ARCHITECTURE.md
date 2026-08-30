# Architecture

## Layout

| Path | Responsibility |
| --- | --- |
| `docker/grafana/Dockerfile` | Build plugin `dist/` from pinned `timeseries-grafana`, copy into Grafana 13.1.0 OSS |
| `docker/baselines/Dockerfile` | Static `cmd/baselines` from pinned `timeseries-baselines` |
| `charts/timeseries` | Umbrella Helm chart |
| `charts/timeseries/charts/` | Grafana community subchart (fetched, gitignored) |
| `ci/values.yaml` | Dummy broker URLs for `helm lint` / `helm template` |

Plugin and worker git pins are `ARG` defaults in the Dockerfiles (`PLUGIN_REF=549d4ac43bb2540f59a8d86ecb5439312c98f35f`, `BASELINES_REF=ee71550923faceb4d019a56cd2be065f607cdf6f`).

## Cluster data flow

Grafana (custom image) queries existing datasources and runs `POST /api/plugins/eduardkolotushin-forecast-app/resources/forecast` in-process.

The baselines worker runs as a sidecar in the Grafana pod. It reads existing Druid SQL, fits minute-of-week, and writes to an existing Kafka baselines topic.

Kafka, Druid, Prometheus, OpenSearch, and Postgres are not in this chart. Optional datasource URLs (`druidUrl`, `prometheusUrl`, `opensearchUrl`, `postgres`) provision Grafana datasources when set. The same `postgres` values provision `FORECAST_STORE_*` (Grafana container), app jsonData, and Forecast datasource jsonData for fitted snapshots. Grafana 12.4+ does not forward host `FORECAST_STORE_*` into plugin processes. The sibling sandbox can install the servers with `make helm-up`.

## Grafana image

1. Node 22: `npm ci` + `npm run build` in the pinned plugin repo (webpack `dist/`).
2. Go 1.26: `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dist/gpx_forecast_linux_amd64 ./pkg` and copy that binary into `dist/forecast-datasource/`.
3. `grafana cli plugins install grafadruid-druid-datasource grafana-opensearch-datasource`.
4. Copy forecast `dist/` and the third-party plugins into `/opt/grafana-plugins`.
5. `GF_PATHS_PLUGINS=/opt/grafana-plugins` and `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS` for the forecast app, overlay panel, and forecast datasource IDs.
6. Run as uid `472`.

Prometheus and Postgres are Grafana core; they are not installed via `grafana cli`.

The Grafana Helm subchart must set `grafana.ini.paths.plugins` to `/opt/grafana-plugins`. A PVC at `/var/lib/grafana` then keeps sqlite/dashboards without overlaying the baked plugins.

## Worker image

`CGO_ENABLED=0` build of `./cmd/baselines`, distroless static nonroot, entrypoint `/baselines`. Config is process env (see `timeseries-baselines` ARCHITECTURE). No HTTP port. Kubernetes restarts the Grafana pod if the sidecar exits.

## Helm

- Subchart `grafana` from `https://grafana-community.github.io/helm-charts`, condition `grafana.enabled`.
- Parent templates: forecast-app ConfigMap, forecast datasource ConfigMap, forecast-store env ConfigMap (`FORECAST_STORE_*`, Grafana `envFromConfigMaps`), optional Druid / Prometheus / OpenSearch / Postgres datasource ConfigMaps (`optional: true` mounts), baselines env ConfigMap.
- Worker container: Grafana `extraContainers` (tpl’d with the release name so it can `envFrom` `{{ .Release.Name }}-baselines-env`).
- One Grafana replica. Do not scale out; duplicate ticks republish the same lead point.
- The worker cannot run if Grafana is disabled.
