# TwentyCRM Kubernates Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/twentycrm)](https://artifacthub.io/packages/search?repo=twentycrm)
[![Release](https://img.shields.io/github/v/tag/Kaiwhodevs/twentycrm?label=chart&sort=semver)](https://github.com/Kaiwhodevs/twentycrm/tags)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Signed with cosign](https://img.shields.io/badge/signed-cosign-2f7de1.svg)](charts/twentycrm/README.md#security--supply-chain)

A production-ready Helm chart for [**Twenty CRM**](https://github.com/twentyhq/twenty),
packaged for Kubernetes and distributed via **OCI on GHCR**.

It mirrors the official
[`twenty-docker` compose file](https://raw.githubusercontent.com/twentyhq/twenty/main/packages/twenty-docker/docker-compose.yml)
exactly (same services, same defaults, same environment variables), so a default
install behaves like `docker compose up`, just on Kubernetes. Upstream images,
Apache-2.0 licensed, cosign signed.

## Install

```bash
helm install twenty oci://ghcr.io/kaiwhodevs/twentycrm \
  --version v2.8.3 \
  --set config.serverUrl=https://crm.example.com
```

Full documentation lives in the chart's README:
**[charts/twentycrm/README.md](charts/twentycrm/README.md)**.

| | |
| --- | --- |
| Registry | `oci://ghcr.io/kaiwhodevs/twentycrm` |
| Artifact Hub | https://artifacthub.io/packages/helm/twentycrm/twentycrm |
| Upstream | [twentyhq/twenty](https://github.com/twentyhq/twenty) |

## Repository layout

```text
.
├── charts/
│   └── twentycrm/        # the Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values.schema.json  # validates values on install/upgrade
│       ├── templates/
│       ├── ci/                 # values used by automated install tests
│       ├── examples/           # ready-to-use values files
│       └── README.md           # chart documentation
├── .github/workflows/          # release automation (see below)
├── artifacthub-repo.yml        # Artifact Hub repository metadata
├── CONTRIBUTING.md
├── SECURITY.md
└── LICENSE
```

## Automation

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `check-upstream-release.yml` | every 6 h | Detect new Twenty releases and bump + tag the chart |
| `release-chart.yml` | tag `v*` | Package, push to GHCR, and cosign-sign the chart |
| `publish-artifacthub-metadata.yml` | `artifacthub-repo.yml` change | Publish repo metadata for the Verified Publisher badge |

See [`charts/twentycrm/README.md`](charts/twentycrm/README.md) for
configuration, production usage, upgrades, and signature verification.

## Contributing & security

- [CONTRIBUTING.md](CONTRIBUTING.md) - how to propose changes and test locally
- [SECURITY.md](SECURITY.md) - how to report a vulnerability

## License

[Apache-2.0](LICENSE). Twenty CRM itself is developed by
[twentyhq/twenty](https://github.com/twentyhq/twenty) under its own license; this
chart only references the upstream container images.
