# Static baselines worker. Source is fetched from GitHub; not copied from a sibling checkout.
ARG BASELINES_REF=1da4af37f3c5aa1e777c4fa2a70fe3dd1114e377

FROM golang:1.26-bookworm AS build
ARG BASELINES_REF
WORKDIR /src
RUN curl -fsSL "https://github.com/eduard-kolotushin/timeseries-baselines/archive/${BASELINES_REF}.tar.gz" \
    | tar -xz --strip-components=1 \
 && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /baselines ./cmd/baselines

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /baselines /baselines
USER nonroot
ENTRYPOINT ["/baselines"]
