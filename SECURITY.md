# Security Policy

## Supply chain

Every released chart is:

- **Signed with [cosign](https://github.com/sigstore/cosign)** (keyless, via GitHub
  Actions OIDC) and recorded in the Rekor transparency log.
- **Schema validated** via a bundled `values.schema.json`.

Verify a release before installing:

```bash
cosign verify ghcr.io/kaiwhodevs/twentycrm:v2.8.3 \
  --certificate-identity-regexp '^https://github.com/Kaiwhodevs/twentycrm/.github/workflows/release-chart.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Reporting a vulnerability

If you find a security issue in this chart (the packaging), please report it
privately via [GitHub Security Advisories](https://github.com/Kaiwhodevs/twentycrm/security/advisories/new)
rather than opening a public issue.

Please include:

- The affected chart version.
- A description of the issue and its impact.
- Steps to reproduce, if possible.

Vulnerabilities in **Twenty CRM itself** (the application) should be reported
upstream at [twentyhq/twenty](https://github.com/twentyhq/twenty/security).

## Scope

This policy covers the Helm chart and its release automation. It does not cover the
upstream `twentycrm/twenty`, `postgres`, or `redis` container images, which are
maintained by their respective projects.
