{{/*
Expand the name of the chart.
*/}}
{{- define "twentycrm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "twentycrm.fullname" -}}
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
Namespace (allows override, mirrors common chart conventions).
*/}}
{{- define "twentycrm.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Chart label (name + version).
*/}}
{{- define "twentycrm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels (includes user-supplied commonLabels).
*/}}
{{- define "twentycrm.labels" -}}
helm.sh/chart: {{ include "twentycrm.chart" . }}
{{ include "twentycrm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: twenty
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "twentycrm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "twentycrm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations (applied to every object's metadata).
*/}}
{{- define "twentycrm.annotations" -}}
{{- with .Values.commonAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Component resource names.
*/}}
{{- define "twentycrm.serverName" -}}{{ include "twentycrm.fullname" . }}-server{{- end }}
{{- define "twentycrm.workerName" -}}{{ include "twentycrm.fullname" . }}-worker{{- end }}
{{- define "twentycrm.dbName" -}}{{ include "twentycrm.fullname" . }}-db{{- end }}
{{- define "twentycrm.redisName" -}}{{ include "twentycrm.fullname" . }}-redis{{- end }}
{{- define "twentycrm.configMapName" -}}{{ include "twentycrm.fullname" . }}-config{{- end }}

{{/*
Fully-qualified, in-cluster service hostnames.
*/}}
{{- define "twentycrm.serverHost" -}}
{{- printf "%s.%s.svc.%s" (include "twentycrm.serverName" .) (include "twentycrm.namespace" .) .Values.clusterDomain -}}
{{- end }}
{{- define "twentycrm.dbHost" -}}
{{- if .Values.externalDatabase.enabled }}{{ .Values.externalDatabase.host }}
{{- else if .Values.postgresql.host }}{{ .Values.postgresql.host }}
{{- else }}{{ printf "%s.%s.svc.%s" (include "twentycrm.dbName" .) (include "twentycrm.namespace" .) .Values.clusterDomain }}{{- end }}
{{- end }}
{{- define "twentycrm.redisHost" -}}
{{- printf "%s.%s.svc.%s" (include "twentycrm.redisName" .) (include "twentycrm.namespace" .) .Values.clusterDomain -}}
{{- end }}

{{/*
Name of the generated Secret this chart creates from values.
*/}}
{{- define "twentycrm.generatedSecretName" -}}
{{- include "twentycrm.fullname" . }}-secret
{{- end }}

{{/*
Secret that holds the server/worker sensitive env (APP_SECRET, ENCRYPTION_KEY,
FALLBACK_ENCRYPTION_KEY, PG_DATABASE_URL): the user-supplied secret.secretRef, or
the generated Secret.
*/}}
{{- define "twentycrm.mainSecretName" -}}
{{- if .Values.secret.secretRef }}{{ tpl .Values.secret.secretRef . }}{{- else }}{{ include "twentycrm.generatedSecretName" . }}{{- end }}
{{- end }}

{{/*
Are we using an external database? (mutually exclusive with the bundled one.)
*/}}
{{- define "twentycrm.bundledDb" -}}
{{- if and (not .Values.externalDatabase.enabled) .Values.postgresql.enabled }}true{{- end }}
{{- end }}

{{/*
Secret + key holding the PostgreSQL password. External DB -> externalDatabase;
bundled DB -> secret.db (its secretRef or the generated Secret).
*/}}
{{- define "twentycrm.dbPasswordSecretName" -}}
{{- if .Values.externalDatabase.enabled }}{{ tpl (required "externalDatabase.secretRef is required when externalDatabase.enabled is true" .Values.externalDatabase.secretRef) . }}
{{- else if .Values.secret.db.secretRef }}{{ tpl .Values.secret.db.secretRef . }}
{{- else }}{{ include "twentycrm.generatedSecretName" . }}{{- end }}
{{- end }}
{{- define "twentycrm.dbPasswordKey" -}}
{{- if .Values.externalDatabase.enabled }}{{ (.Values.externalDatabase.secretRefKey).password | default "database_password" }}
{{- else }}{{ (.Values.secret.db.secretRefKey).password | default "database_password" }}{{- end }}
{{- end }}

{{/*
Assembled connection parameters (external DB or bundled postgres).
*/}}
{{- define "twentycrm.dbUser" -}}
{{- if .Values.externalDatabase.enabled }}{{ .Values.externalDatabase.user }}{{- else }}{{ .Values.postgresql.auth.username }}{{- end }}
{{- end }}
{{- define "twentycrm.dbPort" -}}
{{- if .Values.externalDatabase.enabled }}{{ .Values.externalDatabase.port }}{{- else }}{{ .Values.postgresql.port }}{{- end }}
{{- end }}
{{- define "twentycrm.dbDatabase" -}}
{{- if .Values.externalDatabase.enabled }}{{ .Values.externalDatabase.database }}{{- else }}{{ .Values.postgresql.auth.database }}{{- end }}
{{- end }}
{{- define "twentycrm.dbSslParam" -}}
{{- if and .Values.externalDatabase.enabled .Values.externalDatabase.ssl }}?sslmode=require{{- end }}
{{- end }}

{{/*
Whether the chart needs to generate a Secret from values.
Returns "true" or "".
*/}}
{{- define "twentycrm.generatesSecret" -}}
{{- if or (not .Values.secret.secretRef) (and (eq (include "twentycrm.bundledDb" .) "true") (not .Values.secret.db.secretRef)) -}}
true
{{- end }}
{{- end }}

{{/*
Sensitive env for the server & worker. Fixed fields mapped to Twenty's env vars;
keys come from secret.secretRefKey (lowercase convention). PG_DATABASE_URL is
read from the Secret in secretRef mode, or assembled at runtime via $(VAR)
interpolation (password sourced via secretKeyRef, never inlined into values).
*/}}
{{- define "twentycrm.serverSecretEnv" -}}
{{- $name := include "twentycrm.mainSecretName" . -}}
{{- $rk := .Values.secret.secretRefKey | default dict -}}
- name: APP_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $name }}
      key: {{ $rk.appSecret | default "app_secret" }}
- name: ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $name }}
      key: {{ $rk.encryptionKey | default "encryption_key" }}
- name: FALLBACK_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $name }}
      key: {{ $rk.fallbackEncryptionKey | default "fallback_encryption_key" }}
      optional: true
{{- if .Values.secret.secretRef }}
- name: PG_DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $name }}
      key: {{ $rk.databaseUrl | default "database_url" }}
{{- else }}
{{- if not (or .Values.externalDatabase.enabled (eq (include "twentycrm.bundledDb" .) "true")) }}
{{- fail "No database configured: enable postgresql, set externalDatabase.enabled, or provide a full URL via secret.secretRef (databaseUrl)." }}
{{- end }}
- name: TWENTY_PG_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "twentycrm.dbPasswordSecretName" . }}
      key: {{ include "twentycrm.dbPasswordKey" . }}
- name: PG_DATABASE_URL
  value: {{ printf "postgres://%s:$(TWENTY_PG_PASSWORD)@%s:%v/%s%s" (include "twentycrm.dbUser" .) (include "twentycrm.dbHost" .) (include "twentycrm.dbPort" .) (include "twentycrm.dbDatabase" .) (include "twentycrm.dbSslParam" .) | quote }}
{{- end }}
{{- end }}

{{/*
POSTGRES_PASSWORD for the bundled db pod (secretKeyRef -> secret.db).
*/}}
{{- define "twentycrm.dbPasswordEnv" -}}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "twentycrm.dbPasswordSecretName" . }}
      key: {{ include "twentycrm.dbPasswordKey" . }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "twentycrm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "twentycrm.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Render a fully-qualified image reference, honouring global.imageRegistry.
Usage: include "twentycrm.imageRef" (dict "image" .Values.image "tag" $tag "global" .Values.global)
*/}}
{{- define "twentycrm.imageRef" -}}
{{- $registry := .image.registry | default .global.imageRegistry -}}
{{- $ref := printf "%s:%s" .image.repository .tag -}}
{{- if $registry }}{{ printf "%s/%s" $registry $ref }}{{ else }}{{ $ref }}{{ end -}}
{{- end }}

{{/*
Server / worker image (image.tag falls back to .Chart.AppVersion).
*/}}
{{- define "twentycrm.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- include "twentycrm.imageRef" (dict "image" .Values.image "tag" $tag "global" .Values.global) -}}
{{- end }}

{{/*
Merged image pull secrets (global + chart-level).
*/}}
{{- define "twentycrm.imagePullSecrets" -}}
{{- $secrets := concat (.Values.global.imagePullSecrets | default list) (.Values.imagePullSecrets | default list) | uniq -}}
{{- with $secrets }}
imagePullSecrets:
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Resolve a storageClass: per-component value, else global.storageClass.
Usage: include "twentycrm.storageClass" (dict "value" .Values.x.persistence.storageClass "global" .Values.global)
*/}}
{{- define "twentycrm.storageClass" -}}
{{- $sc := .value | default .global.storageClass -}}
{{- if $sc }}
storageClassName: {{ $sc | quote }}
{{- end }}
{{- end }}

{{/*
REDIS_URL - default redis://<release>-redis:6379 (mirrors the compose default),
or externalRedis.url when set.
*/}}
{{- define "twentycrm.redisUrl" -}}
{{- if .Values.externalRedis.url }}
{{- .Values.externalRedis.url }}
{{- else }}
{{- printf "redis://%s:%v" (include "twentycrm.redisHost" .) (.Values.redis.service.port | int) }}
{{- end }}
{{- end }}

{{/*
APP_SECRET - explicit value, else reuse the value already stored in the
generated Secret (upgrade-stable), else generate a random one. This makes a
default `helm install` work out of the box (like `docker compose up`).
*/}}
{{- define "twentycrm.appSecret" -}}
{{- if .Values.secret.appSecret }}
{{- .Values.secret.appSecret }}
{{- else }}
{{- $key := .Values.secret.secretRefKey.appSecret | default "app_secret" }}
{{- $existing := lookup "v1" "Secret" (include "twentycrm.namespace" .) (include "twentycrm.generatedSecretName" .) }}
{{- if and $existing (index ($existing.data | default dict) $key) }}
{{- index $existing.data $key | b64dec }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
ENCRYPTION_KEY - same generate-and-persist behaviour as appSecret.
*/}}
{{- define "twentycrm.encryptionKey" -}}
{{- if .Values.secret.encryptionKey }}
{{- .Values.secret.encryptionKey }}
{{- else }}
{{- $key := .Values.secret.secretRefKey.encryptionKey | default "encryption_key" }}
{{- $existing := lookup "v1" "Secret" (include "twentycrm.namespace" .) (include "twentycrm.generatedSecretName" .) }}
{{- if and $existing (index ($existing.data | default dict) $key) }}
{{- index $existing.data $key | b64dec }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
PostgreSQL password - explicit secret.db.password, else reuse the generated one
(upgrade-stable), else random.
*/}}
{{- define "twentycrm.dbPassword" -}}
{{- if .Values.secret.db.password }}
{{- .Values.secret.db.password }}
{{- else }}
{{- $key := .Values.secret.db.secretRefKey.password | default "database_password" }}
{{- $existing := lookup "v1" "Secret" (include "twentycrm.namespace" .) (include "twentycrm.generatedSecretName" .) }}
{{- if and $existing (index ($existing.data | default dict) $key) }}
{{- index $existing.data $key | b64dec }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}
{{- end }}
