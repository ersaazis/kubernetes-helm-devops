# Kubernetes Helm DevOps

Production-oriented Helm configuration for platform and DevOps components.

This repository is intended to be reconciled by Argo CD. The current bootstrap
flow installs Argo CD first, prepares Vault for Kubernetes authentication, and
then lets Argo CD manage platform applications from this Git repository.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `charts/external-secrets` | Wrapper chart for External Secrets Operator and Vault `ClusterSecretStore` bootstrap resources. |
| `charts/argocd-apps` | App-of-apps chart that renders an Argo CD `AppProject` and `Application` resources. |
| `docs/` | Implementation tutorials and troubleshooting guides. |
| `scripts/validate-charts.sh` | Local Helm lint/template validation. |

## Architecture

The platform secret flow is:

```text
Vault KV v2 -> External Secrets Operator -> Kubernetes Secret -> workloads
```

The GitOps flow is:

```text
Git repository -> Argo CD Application -> Helm chart render -> Kubernetes resources
```

The default Argo CD application in this repo deploys `charts/external-secrets`
from `git@github.com:ersaazis/kubernetes-helm-devops.git` and uses sync wave
`-10` so secret infrastructure is reconciled before dependent workloads.

## Documentation

Start here:

- [Documentation index](docs/README.md)
- [Install Argo CD](docs/01-install-argocd.md)
- [Set up Vault](docs/02-setup-vault.md)
- [Deploy Argo CD apps](docs/03-deploy-argocd-apps.md)
- [Verify and troubleshoot](docs/04-verify-troubleshooting.md)

## Validation

Run chart validation before pushing changes:

```bash
./scripts/validate-charts.sh
```

Useful targeted renders:

```bash
helm template external-secrets charts/external-secrets \
  -n external-secrets \
  -f charts/external-secrets/values.production.yaml \
  --set external-secrets.installCRDs=false

helm template kubernetes-helm-devops charts/argocd-apps \
  -n argocd \
  -f charts/argocd-apps/values.production.yaml
```

## Secret Handling

Do not commit Vault tokens, Kubernetes service account JWTs, private keys, or
raw application secrets. Keep runtime secret material in Vault and expose it to
Kubernetes through External Secrets.
