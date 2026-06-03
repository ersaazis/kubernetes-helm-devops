# Kubernetes Helm DevOps Config

Production-oriented Helm configs for platform and DevOps utilities.

## DevOps and Platform Charts

| Chart | Source | Main values block | Default image policy | Auth policy |
| --- | --- | --- | --- | --- |
| `charts/external-secrets` | External Secrets Operator dependency | `external-secrets.*` | `ghcr.io/external-secrets/external-secrets:v2.5.0` | bootstrap sync via `vaultStore.*` + `externalSecret.*` |

### Vault Authentication Setup (Kubernetes Auth Method)

The External Secrets Operator (ESO) uses the Kubernetes Auth Method to authenticate with Vault.

#### Configuration Steps

1. **Enable Kubernetes Auth in Vault**:
   ```bash
   vault auth enable kubernetes
   ```

2. **Configure Vault's Kubernetes Auth Method**:
   Configure the API host, the CA certificate of the Kubernetes cluster, and disable local CA JWT to use the client token for the TokenReview:
   ```bash
   vault write auth/kubernetes/config \
     kubernetes_host="https://desktop-control-plane:61829" \
     kubernetes_ca_cert=@/tmp/k8s-ca.crt \
     disable_local_ca_jwt=true
   ```
   > [!NOTE]
   > The `kubernetes_host` must match a name in the Subject Alternative Name (SAN) list of the Kubernetes API server's certificate. In local Docker Desktop environments, mapping `desktop-control-plane` to the host gateway IP (e.g., `192.168.65.254`) in the Vault container's `/etc/hosts` resolves TLS hostname validation mismatches.

3. **Define a Vault Policy and Role**:
   Create a read-only policy for database secrets:
   ```hcl
   path "databases/data/*" {
     capabilities = ["read"]
   }
   path "databases/metadata/*" {
     capabilities = ["list", "read"]
   }
   ```
   Write the role binding it to the `external-secrets` ServiceAccount in the `external-secrets` namespace:
   ```bash
   vault write auth/kubernetes/role/external-secrets \
     bound_service_account_names=external-secrets \
     bound_service_account_namespaces=external-secrets \
     policies=external-secrets \
     ttl=1h
   ```

4. **Grant Auth Delegator Role in Kubernetes**:
   Grant the `system:auth-delegator` ClusterRole to the `external-secrets` ServiceAccount so that it is authorized to perform TokenReview validation requests:
   ```yaml
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: external-secrets-auth-delegator
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: system:auth-delegator
   subjects:
   - kind: ServiceAccount
     name: external-secrets
     namespace: external-secrets
   ```

## Argo CD GitOps Chart

`charts/argocd-apps` renders Argo CD resources for this repo in app-of-apps style:

- one `AppProject`
- one `Application` per deployable chart (1 total)

Sync wave policy in defaults:

- `-10`: `external-secrets`

Install/update example:

```bash
helm upgrade --install platform-devops-prod charts/argocd-apps \
  -n argocd \
  -f charts/argocd-apps/values.production.yaml \
  -f /path/to/argocd-apps.production.real.yaml \
  --set argo.repoURL=https://github.com/acme/kubernetes-helm-devops.git \
  --set argo.targetRevision=main
```

Required real values:

- `argo.repoURL`
- `argo.targetRevision`

Argo CD overlays in repo (referenced by generated Applications):

- `charts/external-secrets/values.argocd.production.yaml`

Production best practices:

- Use immutable `argo.targetRevision` (Git tag or commit SHA), not a moving branch.
- Keep environment-specific Helm value files in Git and reference them via `applications.<name>.valueFiles`.
- Keep secrets out of chart values; use External Secrets (`ClusterSecretStore` + `ExternalSecret`) for runtime secret material.

## Validation

```bash
./scripts/validate-charts.sh
```

`validate-charts.sh` runs default renders for all charts.
