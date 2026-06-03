# Contributing

Thanks for your interest in improving the Twenty CRM Helm chart.

## Local development

The chart lives in [`charts/twentycrm`](charts/twentycrm). You need
[Helm](https://helm.sh) 3.8+ installed.

```bash
# Lint
helm lint charts/twentycrm

# Render the templates with the default values
helm template twenty charts/twentycrm

# Render with an example values file
helm template twenty charts/twentycrm -f charts/twentycrm/examples/production.yaml
```

### Validate against the Kubernetes API

Schema-validate the rendered manifests with
[kubeconform](https://github.com/yannh/kubeconform):

```bash
helm template twenty charts/twentycrm \
  | kubeconform -strict -summary -kubernetes-version 1.29.0 -schema-location default
```

## Guidelines

- Keep the chart faithful to the upstream
  [`docker-compose.yml`](https://raw.githubusercontent.com/twentyhq/twenty/main/packages/twenty-docker/docker-compose.yml):
  same services, defaults, and environment variables.
- Sensitive values belong in the Secret; everything else in the ConfigMap.
- Update `values.schema.json` and the README configuration table when you add or
  rename a value.
- Run `helm lint` and `kubeconform` before opening a pull request.
- Do not bump `Chart.yaml`/`values.yaml` versions by hand - the
  `check-upstream-release.yml` workflow tracks upstream releases automatically.

## Versioning

The chart version (and `appVersion`) match the upstream Twenty release tag exactly,
including the leading `v` (for example `v2.8.3`).

## Pull requests

1. Fork and create a feature branch.
2. Make your change with a clear description of what and why.
3. Ensure lint and validation pass.
4. Open a pull request against `main`.
