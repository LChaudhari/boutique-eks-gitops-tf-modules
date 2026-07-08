{{/*
Application name. Defaults to the Helm release name; override with nameOverride.
*/}}
{{- define "app.name" -}}
{{- default .Release.Name .Values.nameOverride -}}
{{- end -}}

{{/*
Namespace the app workloads land in. Defaults to the release namespace.
*/}}
{{- define "app.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace -}}
{{- end -}}

{{/*
Name of the chart-managed Secret. Defaults to "<app>-secrets".
*/}}
{{- define "app.secretName" -}}
{{- default (printf "%s-secrets" (include "app.name" .)) .Values.secret.name -}}
{{- end -}}

{{/*
Fully-qualified image for a service.
Usage: {{ include "app.image" (dict "svc" . "root" $) }}
  registry/<image|name>:<per-service tag | global.imageTag>
*/}}
{{- define "app.image" -}}
{{- $svc := .svc -}}
{{- $root := .root -}}
{{- $repo := default $svc.name $svc.image -}}
{{- $tag := default $root.Values.global.imageTag $svc.tag -}}
{{- printf "%s/%s:%s" $root.Values.global.registry $repo $tag -}}
{{- end -}}

{{/*
Effective database host: the in-cluster service name, or the external host (RDS).
*/}}
{{- define "app.dbHost" -}}
{{- if eq .Values.database.mode "external" -}}
{{- .Values.database.host -}}
{{- else -}}
{{- .Values.database.name -}}
{{- end -}}
{{- end -}}
