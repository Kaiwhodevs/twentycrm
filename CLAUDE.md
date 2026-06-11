# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A production Helm chart for [Twenty CRM](https://github.com/twentyhq/twenty), distributed via **OCI on GHCR** at `oci://ghcr.io/kaiwhodevs/twentycrm`. The chart mirrors the official [twenty-docker `docker-compose.yml`](https://github.com/twentyhq/twenty/blob/main/packages/twenty-docker/docker-compose.yml) — same services (`server`, `worker`, `db`, `redis`), same env vars, same defaults. The single chart lives in `charts/twentycrm/`; everything at repo root (README, workflows, `artifacthub-repo.yml`) is packaging/distribution scaffolding.

## Commands

```bash
# Lint + render (run from repo root). The "v-prefixed version is not valid SemVerV2"
# warning is EXPECTED and non-failing — see Versioning below.
helm lint charts/twentycrm
helm template t charts/twentycrm -f charts/twentycrm/ci/ci-values.yaml

# Strict schema validation of rendered output (what CI effectively checks)
helm template t charts/twentycrm -f charts/twentycrm/ci/ci-values.yaml > /tmp/m.yaml
kubeconform -strict -summary /tmp/m.yaml      # NOTE: output file MUST end in .yaml

# Render a specific scenario before changing secret/DB logic
helm template t charts/twentycrm -f charts/twentycrm/examples/secret-free.yaml
helm template t charts/twentycrm -f charts/twentycrm/examples/external-services.yaml

helm package charts/twentycrm --destination dist   # produces twentycrm-<version>.tgz
```

There is no app code and no unit-test runner — "tests" means rendering the chart across the `examples/*.yaml` and `ci/ci-values.yaml` value sets and validating with `helm lint` + `kubeconform -strict`. Always re-render the secret-free and external-services examples after touching `_helpers.tpl`, `secret.yaml`, or the deployment env blocks.

## Architecture

**Templating spine — `templates/_helpers.tpl` (36 named templates).** Almost all conditional logic lives here, not in the resource templates. Key decision helpers:

- `twentycrm.bundledDb` → `"true"` when `not externalDatabase.enabled` AND `postgresql.enabled`. **Every** db template (`db-statefulset.yaml`, `db-service.yaml`) is gated on `eq (include "twentycrm.bundledDb" .) "true"`, and the db-connection helpers branch on it.
- `twentycrm.serverSecretEnv` assembles the sensitive env for **both** server and worker: `APP_SECRET`/`ENCRYPTION_KEY`/`FALLBACK_ENCRYPTION_KEY` via `secretKeyRef`, plus `PG_DATABASE_URL` either taken whole from `secret.secretRef` or assembled at runtime as `postgres://user:$(TWENTY_PG_PASSWORD)@host:port/db` using K8s `$(VAR)` interpolation so the password is never inlined.
- `appSecret`/`encryptionKey`/`dbPassword` use `lookup` for **upgrade-stable generation** — re-running `helm upgrade` must not rotate auto-generated secrets.

**Secret + external-DB model (mirrors the Supabase + n8n charts — do not redesign casually).**
- `secret.*`: sensitive fields default to `""`; supply them inline OR point `secret.secretRef` (+ `secret.secretRefKey` field→lowercase-key map) at a pre-made Secret. `secret.db.*` is the bundled-Postgres password sub-block.
- `externalDatabase.*` (n8n-style): when `enabled`, the bundled Postgres is **not** deployed; non-sensitive fields live in values, password comes from `externalDatabase.secretRef`. There is intentionally **no** `externalDatabase.url` field.
- The secret-free path (everything via `secretRef`) is the production default — real secrets must never land in values or release history.

**Shared local storage co-location.** With `config.storage.type=local`, `server` and `worker` share one RWO PVC (`local-data-pvc.yaml`). To make the default work on multi-node clusters without RWX, `worker-deployment.yaml` carries a `podAffinity` (`requiredDuringScheduling`, `topologyKey: kubernetes.io/hostname`) co-locating the worker onto the server's node — gated on `localStorage.persistence.enabled` and overridable via `worker.affinity`. Switching to `config.storage.type=s3` removes this constraint.

**Two raw-env escape hatches, different shapes — keep them straight.** Top-level `extraEnv` is a **map** → ConfigMap (non-sensitive only). `server.extraEnv` / `worker.extraEnv` are **lists** appended to the container `env:` and support `valueFrom` (`secretKeyRef`/`configMapKeyRef`) — the path for sensitive integration creds like `EMAIL_SMTP_PASSWORD`.

**Fresh-install correctness.** `config.storage.type` defaults to `local` (omitting `STORAGE_TYPE` makes Twenty fail to boot) and `podSecurityContext.fsGroup: 1000` is set so the app pods (uid/gid 1000) can write the PVC. Postgres self-chowns as root, so the db StatefulSet does not use fsGroup. See the chart README's Troubleshooting section (`STORAGE_TYPE` error, `EACCES`, the empty-`core`-schema trap).

`values.schema.json` is hand-maintained and must be updated alongside any new top-level value key (it powers ArtifactHub's "Values Schema" badge).

## Versioning & release flow (critical, non-obvious)

**Chart version tracks the Twenty Docker Hub image tag, NOT GitHub releases.** Twenty cuts a GitHub release only at `vX.Y.0` but publishes patch **images** (`vX.Y.Z`) without matching releases (e.g. `v2.8.0` image was never published — the v2.8 line starts at `v2.8.3`). So always resolve the target from Docker Hub:

```bash
curl -s "https://hub.docker.com/v2/repositories/twentycrm/twenty/tags/?page_size=100&ordering=last_updated" \
  | jq -r '.results[].name' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
```

Versions are **`v`-prefixed** (`version: v2.8.3`), which Helm flags as non-SemVerV2 but accepts — this is deliberate so the git tag, Chart version, and image tag are identical.

Three workflows chain:
1. `check-upstream-release.yml` (cron every 6h) — compares Docker Hub's newest deployable tag against `Chart.yaml .version`; on a newer one it bumps `version`, `appVersion`, `values.yaml image.tag`, and the `artifacthub.io/images` annotation, commits, and pushes a `v*` git tag. Requires the **`RELEASE_PAT`** secret (a Contents-write PAT) — `GITHUB_TOKEN` deliberately cannot trigger the release workflow. If the chart looks stale vs Docker Hub, suspect an expired `RELEASE_PAT`.
2. `release-chart.yml` (on `v*` tag push) — verifies tag == `Chart.yaml .version`, `helm package`, `helm push` to GHCR, then **cosign keyless** sign (OIDC) → "Signed" badge.
3. `publish-artifacthub-metadata.yml` (on change to `artifacthub-repo.yml`) — `oras push`es it to the `:artifacthub.io` OCI tag.

To re-release by hand, move the tag to the desired commit and push it (`git tag -f vX.Y.Z <sha>; git push -f origin vX.Y.Z`).

## ArtifactHub gotchas (learned the hard way)

- **OCI change-detection hashes only the set of semver version tags** (`sha256(join(versions,","))` in AH's source). Re-releasing the **same** version (new manifest digest, same tag string) does **not** trigger a reprocess — AH never re-reads metadata, so verification/values-schema changes won't take. To force a reprocess you must change the version *set* (publish a new tag). A throwaway **prerelease** like `vX.Y.Z-1` works and sorts *below* the release so it doesn't become "latest"; `main` stays clean if you push it as a **tag-only** commit (not merged).
- **Verified Publisher** requires `artifacthub-repo.yml`'s `repositoryID` to equal the repo's ID in the AH control panel, published to the `:artifacthub.io` tag, AND a reprocess (see above). Recreating the AH repo mints a **new** repositoryID — you must update `artifacthub-repo.yml` and re-publish, then force a reprocess.
- **Same-version re-releases orphan GHCR manifests** (Helm stamps a fresh timestamp → new digest; the old chart manifest + its `.sig` become untagged orphans). Deleting non-semver tags (`.sig`, `artifacthub.io`) and untagged manifests is safe and does **not** change AH's version-set hash, so it won't trigger a reprocess. Deletion needs a `delete:packages` token (the `RELEASE_PAT` is Contents-only), so it's a manual GHCR-UI step.
- The `artifacthub.io/images` annotation IS bumped in lockstep with `version`/`appVersion` (the auto-bumper `sed`s it). The chart **`icon` is deliberately NOT** — it stays pinned to a fixed working ref. Twenty changed its git-tag scheme to `twenty/vX.Y.0`, so a raw ref like `.../twenty/v2.11.2/...logo.svg` **404s**; the logo is version-independent, so leave the icon pinned to a ref that resolves (currently `v2.8.3`) rather than chasing the app version.
