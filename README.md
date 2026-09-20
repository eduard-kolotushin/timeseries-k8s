# timeseries-k8s

Helm chart and container images to run the [`timeseries-grafana`](https://github.com/eduard-kolotushin/timeseries-grafana) forecast plugin and the [`timeseries-baselines`](https://github.com/eduard-kolotushin/timeseries-baselines) worker on Kubernetes.

This repo does not contain plugin or worker source. Local Compose and a Helm path that installs Kafka + Druid + this chart live in [`timeseries-grafana-sandbox`](../timeseries-grafana-sandbox). Open all siblings with [`../timeseries-workspace.code-workspace`](../timeseries-workspace.code-workspace).

See [docs/INTENTIONS.md](docs/INTENTIONS.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What it deploys

- Grafana 13.1 with the unsigned forecast app, overlay panel, and forecast datasource, the Druid datasource plugin, and the OpenSearch datasource plugin baked in
- Optional baselines worker Deployment (minute-of-week fit to Kafka), scaled independently of Grafana

Kafka, Druid, Prometheus, OpenSearch, and Postgres must already exist if you want those datasources. Pass URLs in values. This chart does not run those servers. A full local stack is sibling [`timeseries-grafana-sandbox`](../timeseries-grafana-sandbox) `make helm-up`.

## Images

| Image | Role |
| --- | --- |
| `ghcr.io/eduard-kolotushin/timeseries-grafana` | Grafana OSS + forecast plugin |
| `ghcr.io/eduard-kolotushin/timeseries-baselines` | Worker binary |

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

## Agents

Contributors and coding agents: start with [AGENTS.md](AGENTS.md).
