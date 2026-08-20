# timeseries-k8s

Helm chart and container images to run the [`timeseries-grafana`](https://github.com/eduard-kolotushin/timeseries-grafana) forecast plugin and the [`timeseries-baselines`](https://github.com/eduard-kolotushin/timeseries-baselines) worker on Kubernetes.

This repo does not contain plugin or worker source. Local Compose and a Helm path that installs Kafka + Druid + this chart live in [`timeseries-grafana-sandbox`](../timeseries-grafana-sandbox). Open all siblings with [`../timeseries-workspace.code-workspace`](../timeseries-workspace.code-workspace).

See [docs/INTENTIONS.md](docs/INTENTIONS.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What it deploys

- Grafana 13.1 with the unsigned forecast app/panel and the Druid datasource plugin baked in
- Optional baselines worker sidecar in the Grafana pod (minute-of-week fit to Kafka)

Kafka and Druid must already exist in the cluster. Pass their URLs in values. A full local stack (Kafka + Druid + this chart) is sibling [`timeseries-grafana-sandbox`](../timeseries-grafana-sandbox) `make helm-up`.

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

## Install

```bash
helm dependency update charts/timeseries
helm install timeseries charts/timeseries \
  --set baselines.druidBroker=http://druid-broker.druid.svc:8082 \
  --set baselines.kafkaBrokers=kafka.kafka.svc:9092
```

Optional Druid datasource in Grafana (see `examples/druid-values.yaml`):

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

Disable the worker with `--set baselines.enabled=false --set grafana.extraContainers=""`. Disable Grafana with `--set grafana.enabled=false` (the sidecar cannot run without Grafana).

## Check the chart

```bash
make lint
```

## Agents

Contributors and coding agents: start with [AGENTS.md](AGENTS.md).
