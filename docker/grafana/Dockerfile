# Grafana OSS with the unsigned forecast plugin, grafadruid-druid-datasource, and grafana-opensearch-datasource.
# Plugin source is fetched from GitHub; it is not copied from a sibling checkout.
ARG PLUGIN_REF=861d25d3174b80cef5cc8da1f953091b10a2d476
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
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o dist/gpx_forecast_linux_amd64 ./pkg \
 && mkdir -p dist/forecast-datasource \
 && cp dist/gpx_forecast_linux_amd64 dist/forecast-datasource/gpx_forecast_linux_amd64

FROM grafana/grafana:${GRAFANA_VERSION}
ARG GRAFANA_VERSION
# Pinned: an unpinned `plugins install` silently changes what the images exercise on a rebuild
# (the sandbox Compose file carries the same versions).
USER root
RUN grafana cli --pluginsDir /tmp/cli-plugins plugins install grafadruid-druid-datasource 1.8.0 \
 && grafana cli --pluginsDir /tmp/cli-plugins plugins install grafana-opensearch-datasource 2.34.4 \
 && mkdir -p /opt/grafana-plugins \
 && cp -a /tmp/cli-plugins/. /opt/grafana-plugins/ \
 && rm -rf /tmp/cli-plugins
COPY --from=backend --chown=472:472 /src/dist /opt/grafana-plugins/eduardkolotushin-forecast-app
RUN chown -R 472:472 /opt/grafana-plugins
ENV GF_PATHS_PLUGINS=/opt/grafana-plugins
ENV GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=eduardkolotushin-forecast-app,eduardkolotushin-forecast-panel,eduardkolotushin-forecast-datasource
USER 472
