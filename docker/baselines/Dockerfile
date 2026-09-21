# Static baselines worker. Source is fetched from GitHub; not copied from a sibling checkout.
ARG BASELINES_REF=179a1551e4dd1064b93cbdd42d12fb684a20dfcd

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
