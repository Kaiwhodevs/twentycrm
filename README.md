# twentycrm-chart

A Helm chart for [Twenty CRM](https://github.com/twentyhq/twenty), packaged for
Kubernetes and distributed via **OCI on GHCR**.

The chart mirrors the official
[`twenty-docker` compose file](https://raw.githubusercontent.com/twentyhq/twenty/main/packages/twenty-docker/docker-compose.yml)
— the same four services, the same defaults, and the same environment variables —
just rebuilt as Kubernetes resources.

| Compose service | Kubernetes resources | Image |
| --------------- | -------------------- | ----- |
| `server` | Deployment + Service (port 3000) | `twentycrm/twenty` |
| `worker` | Deployment (`yarn worker:prod`) | `twentycrm/twenty` |
| `db` | StatefulSet + Service | `postgres:16` |
| `redis` | Deployment + Service | `redis` |

- **Chart version tracks the upstream Twenty release** and is `v`-prefixed to match
  it exactly (e.g. `v2.8.0`).
- Non-sensitive environment variables are rendered into a **ConfigMap**; sensitive
  ones into a **Secret**. The Secret can be swapped for one you manage yourself via
  `secret.existingSecret`.

> **Registry:** `oci://ghcr.io/kaiwhodevs/twentycrm-chart`

---

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+ (OCI support is required and enabled by default in 3.8+)
- A default `StorageClass`, or set `*.persistence.storageClass` explicitly
- A way to expose the `server` Service (Ingress controller, `LoadBalancer`, or
  `kubectl port-forward`)

---

## Quickstart

Install straight from GHCR (no `helm repo add` needed for OCI). Like
`docker compose up`, a default install just works — `APP_SECRET` and
`ENCRYPTION_KEY` are auto-generated on first install and preserved across
upgrades:

```bash
helm install twenty oci://ghcr.io/kaiwhodevs/twentycrm-chart \
  --version v2.8.0 \
  --set config.serverUrl=https://crm.example.com
```

Verify and reach the app:

```bash
helm test twenty                                              # probes /healthz
kubectl port-forward svc/twenty-twentycrm-chart-server 3000:3000
# open http://localhost:3000
```

> By default this deploys a bundled PostgreSQL and Redis with the same defaults as
> the compose file (`postgres:16`, `redis`, user/password `postgres`/`postgres`,
> database `default`). **Change the database password and manage the secrets
> yourself before going to production** — see below.

---

## Production usage with an existing Secret

For production, keep secrets out of your `values.yaml` / release history by creating
the Secret yourself (e.g. via a sealed secret, External Secrets Operator, or `kubectl`)
and pointing the chart at it with `secret.existingSecret`.

The Secret **must** contain these keys:

| Key | Description |
| --- | --- |
| `APP_SECRET` | Token-signing secret (`openssl rand -base64 32`) |
| `ENCRYPTION_KEY` | At-rest encryption key (`openssl rand -base64 32`) |
| `FALLBACK_ENCRYPTION_KEY` | Previous key, used during rotation (may be empty) |
| `PG_DATABASE_PASSWORD` | Password for the (bundled) PostgreSQL |
| `PG_DATABASE_URL` | Full connection string used by server & worker |

Create it:

```bash
kubectl create secret generic twenty-secrets \
  --from-literal=APP_SECRET="$(openssl rand -base64 32)" \
  --from-literal=ENCRYPTION_KEY="$(openssl rand -base64 32)" \
  --from-literal=FALLBACK_ENCRYPTION_KEY="" \
  --from-literal=PG_DATABASE_PASSWORD="$(openssl rand -base64 24)" \
  --from-literal=PG_DATABASE_URL="postgres://postgres:CHANGE_ME@twenty-twentycrm-chart-db:5432/default"
```

> Make `PG_DATABASE_PASSWORD` and the password inside `PG_DATABASE_URL` identical, and
> point the host at `<release-name>-twentycrm-chart-db` (or your external database).

Then install with a production `values-prod.yaml`:

```yaml
# values-prod.yaml
config:
  serverUrl: https://crm.example.com
  # Use S3-compatible object storage in production so server & worker do not need
  # to share a ReadWriteMany volume:
  storage:
    type: s3
    s3Region: us-east-1
    s3Name: my-twenty-bucket
    s3Endpoint: ""   # leave empty for AWS S3, or set for MinIO/R2/etc.

secret:
  existingSecret: twenty-secrets

server:
  replicaCount: 2
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { cpu: "2",  memory: 2Gi }

worker:
  replicaCount: 1

postgresql:
  persistence:
    size: 20Gi
    storageClass: gp3

redis:
  persistence:
    enabled: true
    size: 5Gi

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: crm.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: twenty-tls
      hosts:
        - crm.example.com
```

```bash
helm install twenty oci://ghcr.io/kaiwhodevs/twentycrm-chart \
  --version v2.8.0 \
  -f values-prod.yaml
```

### Sensitive S3 / SMTP / OAuth credentials

Anything sensitive (e.g. `EMAIL_SMTP_PASSWORD`, `AUTH_GOOGLE_CLIENT_SECRET`) should go
into the Secret. When generating the Secret from values, add them under
`secret.extraEnv`; non-sensitive integration vars go under `extraEnv` (ConfigMap):

```yaml
extraEnv:                       # -> ConfigMap
  EMAIL_FROM_ADDRESS: contact@example.com
  EMAIL_DRIVER: smtp
  EMAIL_SMTP_HOST: smtp.example.com
  EMAIL_SMTP_PORT: "465"
secret:
  extraEnv:                     # -> Secret
    EMAIL_SMTP_PASSWORD: "..."
```

If you use `existingSecret`, just add those keys to your own Secret instead.

---

## Using an external database / Redis

```yaml
postgresql:
  enabled: false
externalDatabase:
  url: postgres://user:password@my-postgres-host:5432/default

redis:
  enabled: false
externalRedis:
  url: redis://my-redis-host:6379
```

(When generating the Secret, `externalDatabase.url` is written to `PG_DATABASE_URL`.
With `existingSecret`, set `PG_DATABASE_URL` in your Secret directly.)

---

## Upgrades

This chart's version equals the Twenty release it deploys, so upgrading the chart
upgrades Twenty.

```bash
# See what's available
helm show chart oci://ghcr.io/kaiwhodevs/twentycrm-chart --version v2.8.0

# Upgrade, reusing your existing values
helm upgrade twenty oci://ghcr.io/kaiwhodevs/twentycrm-chart \
  --version v2.8.0 \
  -f values-prod.yaml
```

Notes:
- Database migrations run automatically on the **server** at startup
  (`DISABLE_DB_MIGRATIONS` is empty there and forced to `"true"` on the worker, exactly
  as in the compose). Back up your database before a major upgrade.
- Pin `--version` to a specific `vX.Y.Z`; avoid floating tags in production.
- Review the [upstream release notes](https://github.com/twentyhq/twenty/releases)
  for breaking changes between versions.
- The server/worker default to the `Recreate` update strategy because they share a
  `ReadWriteOnce` local-storage volume (a rolling update would deadlock on the
  single-attach PVC). This means a brief restart during upgrades. For zero-downtime
  upgrades, use S3 storage (`config.storage.type=s3`) or an RWX volume and set
  `server.strategy.type=RollingUpdate`.

---

## Configuration

| Key | Default | Description |
| --- | ------- | ----------- |
| `global.imageRegistry` | `""` | Override registry for all images |
| `global.imagePullSecrets` | `[]` | Pull secrets for all pods |
| `global.storageClass` | `""` | Default StorageClass for all PVCs |
| `commonLabels` / `commonAnnotations` | `{}` | Labels/annotations added to every object |
| `clusterDomain` | `cluster.local` | In-cluster DNS domain for service hostnames |
| `nameOverride` / `fullnameOverride` / `namespaceOverride` | `""` | Name/namespace overrides |
| `extraDeploy` | `[]` | Extra raw manifests (templated) to deploy with the release |
| `serviceAccount.create` / `.name` / `.automount` | `true` / `""` / `true` | ServiceAccount settings |
| `image.registry` / `.repository` | `""` / `twentycrm/twenty` | Server/worker image |
| `image.tag` | `v2.8.0` | Image tag (falls back to `.Chart.AppVersion` if empty) |
| `busyboxImage.*` | `busybox:1.36` | Image for dependency-wait init containers and `helm test` |
| `config.serverUrl` | `""` | `SERVER_URL` — public URL of the instance |
| `config.nodePort` | `3000` | `NODE_PORT` |
| `config.disableDbMigrations` | `""` | `DISABLE_DB_MIGRATIONS` (server) |
| `config.disableCronJobsRegistration` | `""` | `DISABLE_CRON_JOBS_REGISTRATION` (server) |
| `config.storage.type` | `""` | `STORAGE_TYPE` (`""` = local, `s3`) |
| `config.storage.s3Region` / `s3Name` / `s3Endpoint` | `""` | S3 storage settings |
| `extraEnv` | `{}` | Extra non-sensitive env → ConfigMap |
| `secret.existingSecret` | `""` | Use a pre-created Secret instead of generating one |
| `secret.appSecret` | `""` | `APP_SECRET` (auto-generated when empty) |
| `secret.encryptionKey` | `""` | `ENCRYPTION_KEY` (auto-generated when empty) |
| `secret.fallbackEncryptionKey` | `""` | `FALLBACK_ENCRYPTION_KEY` |
| `secret.extraEnv` | `{}` | Extra sensitive env → Secret |
| `server.replicaCount` | `1` | Server replicas (ignored when autoscaling is on) |
| `server.strategy` | `Recreate` | Deployment update strategy (RWO volume → Recreate) |
| `server.service.type` / `.port` | `ClusterIP` / `3000` | Server Service |
| `server.startupProbe` | `/healthz`, ~5m budget | Guards slow first-boot migrations |
| `server.livenessProbe` / `.readinessProbe` | `/healthz` | Probe config (set `.enabled=false` to disable) |
| `server.autoscaling.enabled` | `false` | HorizontalPodAutoscaler for the server |
| `server.pdb.enabled` | `false` | PodDisruptionBudget for the server |
| `server.resources` / `worker.resources` | `{}` | Resource requests/limits |
| `server.extraVolumes` / `.extraVolumeMounts` | `[]` | Extra volumes/mounts (also on `worker`) |
| `worker.replicaCount` | `1` | Worker replicas |
| `postgresql.enabled` | `true` | Deploy the bundled PostgreSQL |
| `postgresql.auth.username` / `.password` / `.database` | `postgres` / `postgres` / `default` | DB credentials |
| `postgresql.persistence.*` | `8Gi`, RWO | DB volume |
| `externalDatabase.url` | `""` | External `PG_DATABASE_URL` |
| `redis.enabled` | `true` | Deploy the bundled Redis |
| `redis.maxmemoryPolicy` | `noeviction` | Redis `--maxmemory-policy` |
| `redis.persistence.enabled` | `false` | Persist Redis (switches it to a StatefulSet) |
| `externalRedis.url` | `""` | External `REDIS_URL` |
| `localStorage.persistence.*` | `8Gi`, RWO | Shared `.local-storage` volume |
| `ingress.*` | disabled | Ingress for the server Service |

See [`values.yaml`](values.yaml) for the full, commented list.

### A note on local file storage

With the default `STORAGE_TYPE=local`, the `server` and `worker` pods share a single
`PersistentVolumeClaim` (mirroring the shared `server-local-data` volume in the compose).
A `ReadWriteOnce` volume only works if both pods land on the same node. For multi-node
clusters, either set `localStorage.persistence.accessModes: [ReadWriteMany]` with an RWX
storage class, or — recommended — switch to S3 storage (`config.storage.type=s3`).

### Design notes

- **Faithful to the docker install.** The bundled `db` and `redis` are the plain
  `postgres:16` and `redis` images from the compose — not Bitnami subcharts — so the
  defaults, images, and environment variables match `docker compose up` exactly. Point
  `postgresql.enabled=false` / `redis.enabled=false` at managed services for production.
- **Standard chart conventions.** Recommended `app.kubernetes.io/*` labels, `global.*`
  (image registry / pull secrets / storage class), `commonLabels` / `commonAnnotations`,
  `serviceAccount.automount`, configurable probes, HPA, PodDisruptionBudget,
  `extraVolumes` / `extraDeploy` escape hatches, a `helm test` hook, and a
  `values.schema.json` — so it behaves like any other production Helm chart.

---

## CI/CD — how releases work

Two GitHub Actions workflows keep this chart in lockstep with upstream:

1. **`check-upstream-release.yml`** runs every 6 hours. It reads the latest
   `twentyhq/twenty` release, and if it is newer than `Chart.yaml`'s `version`, it bumps
   `version` + `appVersion` in `Chart.yaml` and `image.tag` in `values.yaml`, commits,
   and pushes a matching `v`-prefixed tag (e.g. `v2.8.0`).
2. **`release-chart.yml`** triggers on that tag. It lints, runs `helm package` (producing
   `twentycrm-chart-<tag>.tgz`), and `helm push`es it to
   `oci://ghcr.io/kaiwhodevs/twentycrm-chart:<tag>`.

> **Setup:** the bump workflow needs a repository secret named **`RELEASE_PAT`** — a PAT
> (or fine-grained token) with `Contents: write`. It is required because a tag pushed
> with the default `GITHUB_TOKEN` cannot trigger another workflow; the PAT lets the tag
> push start `release-chart.yml`. The release workflow itself only needs the built-in
> `GITHUB_TOKEN` (with `packages: write`) to push to GHCR.

You can also cut a release manually:

```bash
git tag v2.8.0 && git push origin v2.8.0
```

---

## License

This packaging is provided as-is. Twenty CRM itself is licensed by
[twentyhq/twenty](https://github.com/twentyhq/twenty).
