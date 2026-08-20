# Architecture

## Layout

| Path | Responsibility |
| --- | --- |
| `docker/grafana/Dockerfile` | Build plugin `dist/` from pinned `timeseries-grafana`, copy into Grafana 13.1.0 OSS |
| `docker/baselines/Dockerfile` | Static `cmd/baselines` from pinned `timeseries-baselines` |
| `charts/timeseries` | Umbrella Helm chart |
| `charts/timeseries/charts/` | Grafana community subchart (fetched, gitignored) |
| `ci/values.yaml` | Dummy broker URLs for `helm lint` / `helm template` |

Plugin and worker git pins are `ARG` defaults in the Dockerfiles (`PLUGIN_REF=781068c725f07041a0e17ff6eae63ce6cce1e8b8`, `BASELINES_REF=ee71550923faceb4d019a56cd2be065f607cdf6f`).

## Cluster data flow

Grafana (custom image) queries existing Druid and runs `POST /api/plugins/eduardkolotushin-forecast-app/resources/forecast` in-process.

The baselines worker reads existing Druid SQL, fits minute-of-week, and writes to an existing Kafka baselines topic.

Kafka and Druid are not in this chart.

## Grafana image

1. Node 22: `npm ci` + `npm run build` in the pinned plugin repo (webpack `dist/`).
2. Go 1.26: `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dist/gpx_forecast_linux_amd64 ./pkg`.
3. `grafana cli plugins install grafadruid-druid-datasource`.
4. Copy forecast `dist/` and the Druid plugin into `/opt/grafana-plugins`.
5. `GF_PATHS_PLUGINS=/opt/grafana-plugins` and `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS` for the two forecast plugin IDs.
6. Run as uid `472`.

The Grafana Helm subchart must set `grafana.ini.paths.plugins` to `/opt/grafana-plugins`. A PVC at `/var/lib/grafana` then keeps sqlite/dashboards without overlaying the baked plugins.

## Worker image

`CGO_ENABLED=0` build of `./cmd/baselines`, distroless static nonroot, entrypoint `/baselines`. Config is process env (see `timeseries-baselines` ARCHITECTURE). No HTTP port; Kubernetes restarts the container if the process exits.

## Helm

- Subchart `grafana` from `https://grafana-community.github.io/helm-charts`, condition `grafana.enabled`.
- Parent templates: forecast-app ConfigMap, optional Druid datasource ConfigMap, worker Deployment.
- Worker `replicaCount` is 1. Do not scale out; duplicate ticks republish the same lead point.
