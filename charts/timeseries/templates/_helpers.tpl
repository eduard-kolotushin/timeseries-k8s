{{/*
Expand the name of the chart.
*/}}
{{- define "timeseries.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "timeseries.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "timeseries.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "timeseries.labels" -}}
helm.sh/chart: {{ include "timeseries.chart" . }}
{{ include "timeseries.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "timeseries.selectorLabels" -}}
app.kubernetes.io/name: {{ include "timeseries.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Parse a Postgres address into "<host>|<port>", so one value serves both spellings the chart
accepts: a bare `host` / `host:port` (as the datasource NOTES show) and a DSN
(`scheme://[user[:pass]@]host[:port][/db]`). Callers split on "|" and keep the 5432 default.
An empty input renders "|5432" — the caller decides whether an empty address means
"not configured" — while a non-empty input without a host fails the render with the value quoted,
instead of quietly provisioning a bogus host.

Usage: {{ include "timeseries.postgresAddress" (dict "raw" .Values.postgres.url) | splitList "|" }}
*/}}
{{- define "timeseries.postgresAddress" -}}
{{- $raw := trim (.raw | default "") -}}
{{- $host := "" -}}
{{- $port := "5432" -}}
{{- if $raw -}}
  {{- $rest := $raw -}}
  {{- if contains "://" $rest -}}
    {{- $rest = regexReplaceAll "^[A-Za-z][A-Za-z0-9+.-]*://" $rest "" -}}
    {{- $rest = regexReplaceAll "^[^/?#]*@" $rest "" -}}
    {{- $rest = regexReplaceAll "[/?#].*$" $rest "" -}}
  {{- end -}}
  {{- $rest = trim $rest -}}
  {{- if contains ":" $rest -}}
    {{- $found := regexFind ":\\d+$" $rest -}}
    {{- if not $found -}}
      {{- fail (printf "postgres address %q has no numeric port: use host, host:port or scheme://user:pass@host:port/db" $raw) -}}
    {{- end -}}
    {{- $port = trimPrefix ":" $found -}}
    {{- $rest = regexReplaceAll ":\\d+$" $rest "" -}}
  {{- end -}}
  {{- $host = $rest -}}
  {{- if not $host -}}
    {{- fail (printf "postgres address %q has no host: use host, host:port or scheme://user:pass@host:port/db" $raw) -}}
  {{- end -}}
{{- end -}}
{{- printf "%s|%s" $host $port -}}
{{- end }}

{{/*
Rollout trigger for the ConfigMaps the Grafana Deployment consumes. Grafana reads provisioning
only at startup and every mount uses subPath (kubelet never updates those in place), so a values
change has to move the pod template. The Grafana subchart does not template `podAnnotations`; the
hooks it does pass through `tpl` — `env`, `envFromConfigMaps[].name`, `envFromSecrets[].name`,
`extraConfigmapMounts.*` — are rendered in the *subchart* context, which sees `grafana.*` values and
`global` but not this chart's `postgres` block. This helper therefore hashes the subchart-visible inputs
that feed `<release>-forecast-app`: `retrainCron`, `pluginToken` and `configRevision`.
A store-only change needs `grafana.configRevision` bumped (see values.yaml).
*/}}
{{- define "timeseries.grafanaConfigChecksum" -}}
{{- printf "%s|%s|%s" (toString .Values.retrainCron) (toString .Values.pluginToken) (toString .Values.configRevision) | sha256sum -}}
{{- end }}

{{/*
String form of an optional worker knob, or "" when the value is absent/empty. `0` is a real
setting for several of them (DRUID_RETRIES), so truthiness is not enough and `toString nil`
("<nil>") must not leak into a ConfigMap.

Usage: {{- with include "timeseries.optional" .Values.baselines.logLevel }}
         LOG_LEVEL: {{ . | quote }}
       {{- end }}
*/}}
{{- define "timeseries.optional" -}}
{{- if or (kindIs "invalid" .) (eq (toString .) "") -}}
{{- else -}}
{{- toString . -}}
{{- end -}}
{{- end }}

