{{- define "argocd-apps.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "argocd-apps.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "argocd-apps.name" . -}}
{{- end -}}
{{- end -}}

{{- define "argocd-apps.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "argocd-apps.labels" -}}
helm.sh/chart: {{ include "argocd-apps.chart" . }}
app.kubernetes.io/name: {{ include "argocd-apps.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "argocd-apps.normalize" -}}
{{- . | lower | replace "_" "-" | replace "." "-" | replace " " "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "argocd-apps.applicationConfig" -}}
{{- $defaults := deepCopy (default dict .root.Values.argo.applicationDefaults) -}}
{{- $app := deepCopy (default dict .app) -}}
{{- toYaml (mergeOverwrite $defaults $app) -}}
{{- end -}}

