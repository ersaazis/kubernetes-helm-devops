# Documentation

Ikuti dokumen ini berurutan untuk bootstrap platform DevOps di cluster Kubernetes.

## Urutan Implementasi

1. [Install Argo CD](01-install-argocd.md)
2. [Setup Vault](02-setup-vault.md)
3. [Deploy Argo CD Apps](03-deploy-argocd-apps.md)
4. [Verify dan Troubleshooting](04-verify-troubleshooting.md)

## Prasyarat

- Akses Kubernetes cluster via `kubectl`.
- `helm` tersedia di mesin operator.
- Vault reachable dari cluster Kubernetes.
- Repo GitHub `git@github.com:ersaazis/kubernetes-helm-devops.git` sudah bisa diakses Argo CD.
- Jangan commit token Vault, service account JWT, SSH private key, atau secret aplikasi.

## Ringkasan Flow

```text
1. Install Argo CD ke namespace argocd
2. Siapkan Vault KV, policy, dan Kubernetes auth
3. Register repository credential ke Argo CD
4. Install chart argocd-apps untuk membuat Application external-secrets
5. Argo CD sync chart external-secrets
6. External Secrets Operator login ke Vault dan membuat Kubernetes Secret sesuai ExternalSecret
```

## Komponen Repo

- `charts/argocd-apps`: membuat `AppProject` dan `Application` Argo CD.
- `charts/external-secrets`: menginstall External Secrets Operator dan membuat dua `ClusterSecretStore` Vault: `databases` dan `prohukum-apps`.
- `charts/external-secrets/values.argocd.production.yaml`: overlay repo-managed yang wajib ada karena Argo CD `Application` memakai `ignoreMissingValueFiles=false`.
