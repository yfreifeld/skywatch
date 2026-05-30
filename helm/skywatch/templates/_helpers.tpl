{{/*
Expand the name of the chart.
*/}}
{{- define "skywatch.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "skywatch.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "skywatch.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "skywatch.name" . }}-frontend
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Worker selector labels
*/}}
{{- define "skywatch.worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "skywatch.name" . }}-worker
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
RabbitMQ service name (provided by bitnami sub-chart)
*/}}
{{- define "skywatch.rabbitmqHost" -}}
{{- printf "%s-rabbitmq" .Release.Name }}
{{- end }}
