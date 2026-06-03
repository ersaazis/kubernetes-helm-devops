# argocd-apps

Production-oriented Argo CD config chart for this monorepo.

This chart renders:

- one `AppProject`
- one `Application` per deployable chart

It excludes `charts/app-template`, because that chart is a Helm library chart and not directly deployable.

It does not install the Argo CD controller.

## Usage

```bash
helm template argocd-apps ./charts/argocd-apps \
  -f ./charts/argocd-apps/values.production.yaml \
  -f /path/to/argocd-apps.production.real.yaml
```

Required real values:

- `argo.repoURL`
- `argo.targetRevision`

Recommended real values file:

```yaml
argo:
  repoURL: https://github.com/acme/kubernetes-helm-config.git
  targetRevision: refs/tags/2026.05.28
```

The generated Applications reference repo-tracked Helm value files, including `values.argocd.production.yaml` for:

- `external-secrets`
- `prohukum45`
- `indonesian_legal_directory`
- `entri`

## Customization

Per-application settings can be overridden from `applications.<name>.*`, for example:

```yaml
applications:
  prohukum45:
    valueFiles:
      - values.production.yaml
      - values.argocd.production.yaml
      - values.argocd.jakarta-prod.yaml
```

This keeps Argo CD state declarative and repo-driven, instead of relying on ad hoc UI edits or inline Helm parameters.

## Notes

- sync wave `-10`: `external-secrets`
- sync wave `0`: databases and platform charts
- sync wave `10`: grouped application charts
- app-of-apps style ordering only matters when this chart itself is reconciled by Argo CD
- `argo.repoURL` validation is strict; render fails if unset
- `requiredValueFiles` validation is strict; render fails if a mandatory repo overlay is removed

## Production Guidance

- Prefer Git tags or commit SHAs for `argo.targetRevision`.
- Keep secrets out of Argo CD Application values; use External Secrets for secret delivery.
- Treat `values.argocd.production.yaml` as repo-managed environment config and replace placeholder registries, hosts, and TLS secret names with real ones before promotion.
