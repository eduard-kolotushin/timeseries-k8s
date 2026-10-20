# timeseries-k8s

Helm chart and container images to run the [`timeseries-grafana`](https://github.com/eduard-kolotushin/timeseries-grafana) forecast plugin and the [`timeseries-baselines`](https://github.com/eduard-kolotushin/timeseries-baselines) worker on Kubernetes.

This repo does not contain plugin or worker source. Local Compose and a Helm path that installs Kafka + Druid + this chart live in [`timeseries-grafana-sandbox`](../timeseries-grafana-sandbox). Open all siblings with [`../timeseries-workspace.code-workspace`](../timeseries-workspace.code-workspace).

See [docs/INTENTIONS.md](docs/INTENTIONS.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What it deploys

- Grafana 13.1 with the unsigned forecast app, overlay panel, and forecast datasource, the Druid datasource plugin, and the OpenSearch datasource plugin baked in
- Optional baselines worker Deployment (minute-of-week fit to Kafka), scaled independently of Grafana
- Optional forecast compute Deployment (`compute.enabled`, v16) that owns fitting and the retrain ticker when enabled
- Optional Vault PKI mTLS for the plugin→compute hop, PVV, Postgres store and Vault itself (`vault.*`, plugin v19–v21); Vault is external

Kafka, Druid, Prometheus, OpenSearch, and Postgres must already exist if you want those datasources. Pass URLs in values. This chart does not run those servers. A full local stack is sibling [`timeseries-grafana-sandbox`](../timeseries-grafana-sandbox) `make helm-up`.

## Images

| Image | Role |
| --- | --- |
| `ghcr.io/eduard-kolotushin/timeseries-grafana` | Grafana OSS + forecast plugin |
| `ghcr.io/eduard-kolotushin/timeseries-baselines` | Worker binary |
| `ghcr.io/eduard-kolotushin/timeseries-forecast-compute` | Optional standalone fit/tick service (`cmd/compute`) |

linux/amd64. Tags are published from this repo on `v*` git tags (first `v0.1.0` after a tag push). Until then, build locally:

```bash
make docker-grafana
make docker-baselines
```

Both Dockerfiles clone a sibling repo by pinned ref (`PLUGIN_REF`, `BASELINES_REF`) over GitHub, not from a local checkout, so the pinned commit must be **pushed** before either build or the CI images job can succeed — a local-only commit makes the fetch 404.

## Install

```bash
make helm-deps
helm install timeseries charts/timeseries \
  --set baselines.druidBroker=http://druid-broker.druid.svc:8082 \
  --set baselines.kafkaBrokers=kafka.kafka.svc:9092
```

`make helm-deps` fetches the Grafana subchart using an isolated Helm repository config (not the global `helm repo list`). Helm 4 otherwise fails if a leftover repo such as Bitnami has a missing cache index.

Optional Druid datasource in Grafana (see `examples/druid-values.yaml`). Prometheus, OpenSearch, and overlay Postgres URLs use the same pattern (`prometheusUrl`, `opensearchUrl`, `postgres`):

```bash
helm install timeseries charts/timeseries -f examples/druid-values.yaml
```

Admin password (Grafana Helm default secret):

```bash
kubectl get secret timeseries-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

Port-forward Grafana:

```bash
kubectl port-forward svc/timeseries-grafana 3000:80
```

## Optional compute service

`compute.enabled=true` deploys `<release>-forecast-compute` and points the app's `computeUrl` at it; the plugin then forwards `POST /forecast` and runs no ticker. It needs `compute.token`, shares the `postgres.*` store and fetches frames from Grafana's own `/api/ds/query` (`compute.grafanaUrl`, defaulting to `http://<release>-grafana:80`). Scale it independently:

```bash
kubectl -n <ns> scale deployment/timeseries-forecast-compute --replicas=4
```

The pod is distroless (no shell); `/forecast` and `/ping` need the bearer token, `/healthz` is the coarse unauthenticated probe.

## Vault PKI mTLS

`vault.enabled=true` points the compute hop at Vault PKI (`vault.addr`, `pkiMount`, `pkiRole`, `certTtl`, `serverName`, `clientCn`, `auth.*`) and switches `computeUrl` to `https`. The per-component switches are `FORECAST_COMPUTE_MTLS` / `_PVV_MTLS` / `_STORE_MTLS`; unset means "that role is configured", explicit `false` keeps that hop plain (Istio shape). v21 adds `vault.mtls` with file paths `vault.clientCertFile` / `vault.clientKeyFile` for a Vault listener that requires a client certificate. The chart renders the paths but does not create the Secret: mount it into both Grafana and compute pods with `grafana.extraVolumes` / `compute.extraVolumes` (and the matching `extraVolumeMounts`). Certificate values are paths, never PEM content.

## Scale the worker

The worker runs as its own Deployment (`<release>-baselines`), independent of Grafana. Replicas divide the metric hashes by rendezvous hashing, so there is no coordinator and no leader:

```bash
kubectl -n <ns> scale deployment/timeseries-baselines --replicas=4
```

Each pod takes `SHARD_ID` from the Downward API (`status.podIP`) and finds its peers through `SHARD_DNS`, the headless Service `<release>-baselines-headless` (`baselines.membership`, default `dns`; set it to `store` to use the Postgres heartbeat instead). Adding or removing one replica moves roughly `1/N` of the hashes; a point published twice is collapsed by the sink, so scale freely.

Set `postgres.url` (plus `database` / `user` / `password`) and the worker persists snapshots to that Postgres and trains on a cron instead of re-reading Druid every tick; `baselines.druidMaxRange`, `druidMaxRps`, `trainConcurrency`, `hashScanTtl` and `defaultRetrainCron` bound those Druid reads. `grafana.retrainCron` and `grafana.pluginToken` configure the plugin's own backend retrainer.

Disable the worker with `--set baselines.enabled=false`. Disable Grafana with `--set grafana.enabled=false` (the worker keeps running).

Full runbook, including the VM path, verification queries, and the negative controls: [`timeseries-baselines/docs/POC.md`](../timeseries-baselines/docs/POC.md) (Русский: [`POC.ru.md`](../timeseries-baselines/docs/POC.ru.md)).

## Check the chart

```bash
make lint
```

`make lint` also renders the sibling sandbox's `helm/timeseries-values.yaml` when that checkout is
present (CI skips it). `make check-pins` fails when a Dockerfile `PLUGIN_REF`/`BASELINES_REF` is
neither the sibling head nor an ancestor of it, which is what CI runs on every pull request; both refs
are bumped in the same pass as the sibling change they carry.

## Agents

Contributors and coding agents: start with [AGENTS.md](AGENTS.md).
