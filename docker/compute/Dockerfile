# Static compute service for the forecast plugin (v16): the plugin's /forecast handler and retrain
# ticker, served standalone so fitting capacity scales without Grafana replicas. Source is fetched
# from GitHub; not copied from a sibling checkout.
ARG PLUGIN_REF=60a982c544beadf7a3263c96aa905b43242a3f4c

FROM golang:1.26-bookworm AS build
ARG PLUGIN_REF
WORKDIR /src
RUN curl -fsSL "https://github.com/eduard-kolotushin/timeseries-grafana/archive/${PLUGIN_REF}.tar.gz" \
    | tar -xz --strip-components=1 \
 && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /gpx_forecast_compute ./cmd/compute

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /gpx_forecast_compute /gpx_forecast_compute
USER nonroot
# The listen address, the shared token and the store/Grafana settings come from the environment
# (FORECAST_COMPUTE_LISTEN / FORECAST_COMPUTE_TOKEN / FORECAST_STORE_* / FORECAST_GRAFANA_*).
ENTRYPOINT ["/gpx_forecast_compute"]
