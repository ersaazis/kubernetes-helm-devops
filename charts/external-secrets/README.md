# external-secrets

Wrapper chart for the official External Secrets Operator chart pinned to `2.5.0`.

This chart installs ESO (with CRDs) and provides optional bootstrap manifests for:

- `ClusterSecretStore` or `SecretStore` (Vault/HCP Vault)
- `ExternalSecret` for auto-sync remote secret to Kubernetes `Secret`

## Quick Start

```bash
helm dependency update charts/external-secrets
helm install external-secrets charts/external-secrets \
  -n external-secrets \
  --create-namespace \
  -f charts/external-secrets/values.production.yaml
```

## Auto-Sync Flow

1. Enable and fill `vaultStore.*`
2. Enable and fill `externalSecret.*`
3. ESO reconciles `ExternalSecret` into target Kubernetes `Secret`

Both bootstrap resources are `false` by default in production values to avoid broken placeholders.

## Argo CD

`charts/argocd-apps` references `charts/external-secrets/values.argocd.production.yaml` and assigns this chart sync wave `-10` so ESO bootstrap lands before dependent workloads.

Production best practice: keep `vaultStore.enabled` and `externalSecret.enabled` disabled until the repo contains real HCP Vault connection details, auth role, and target secret mappings.
