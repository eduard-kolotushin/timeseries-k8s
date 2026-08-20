# Grafana OSS with the unsigned forecast plugin and grafadruid-druid-datasource.
# Plugin source is fetched from GitHub; it is not copied from a sibling checkout.
ARG PLUGIN_REF=781068c725f07041a0e17ff6eae63ce6cce1e8b8
ARG GRAFANA_VERSION=13.1.0

FROM node:22-bookworm AS frontend
ARG PLUGIN_REF
WORKDIR /src
RUN curl -fsSL "https://github.com/eduard-kolotushin/timeseries-grafana/archive/${PLUGIN_REF}.tar.gz" \
    | tar -xz --strip-components=1 \
 && npm ci \
 && npm run build

FROM golang:1.26-bookworm AS backend
WORKDIR /src
COPY --from=frontend /src /src
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dist/gpx_forecast_linux_amd64 ./pkg

FROM grafana/grafana:${GRAFANA_VERSION}
ARG GRAFANA_VERSION
USER root
RUN grafana cli --pluginsDir /tmp/cli-plugins plugins install grafadruid-druid-datasource \
 && mkdir -p /opt/grafana-plugins \
 && cp -a /tmp/cli-plugins/. /opt/grafana-plugins/ \
 && rm -rf /tmp/cli-plugins
COPY --from=backend --chown=472:472 /src/dist /opt/grafana-plugins/eduardkolotushin-forecast-app
RUN chown -R 472:472 /opt/grafana-plugins
ENV GF_PATHS_PLUGINS=/opt/grafana-plugins
ENV GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=eduardkolotushin-forecast-app,eduardkolotushin-forecast-panel
USER 472
