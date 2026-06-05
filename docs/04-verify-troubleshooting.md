# Verifikasi dan Troubleshooting

Gunakan langkah ini untuk mengonfirmasi platform berjalan dan mendiagnosa masalah umum.

## Health Check

Jalankan semua perintah ini setelah deploy; semua harus pass:

```bash
# Argo CD Application
kubectl -n argocd get application external-secrets

# ESO deployment
kubectl -n external-secrets rollout status deploy/external-secrets

# ClusterSecretStore (keduanya harus Valid/Ready=True)
kubectl get clustersecretstore
```

Output target:

```text
NAME               SYNC STATUS   HEALTH STATUS
external-secrets   Synced        Healthy

deployment "external-secrets" successfully rolled out

NAME            AGE   STATUS   CAPABILITIES   READY
databases       ...   Valid    ReadWrite      True
prohukum-apps   ...   Valid    ReadWrite      True
```

## Troubleshooting Umum

**Vault 403 permission denied saat login Kubernetes auth**

Error:
```text
unable to log in with Kubernetes auth: Error making API request.
URL: PUT https://<vault>/v1/auth/kubernetes-local/login
Code: 403
```

Penyebab umum:
- Path auth yang dikonfigurasi di Vault config tidak cocok dengan `vaultStore.auth.kubernetes.mountPath` di Helm.
- Auth lama masih di `auth/kubernetes`, sementara chart repo ini memakai `auth/kubernetes-local`.
- Reviewer service account atau binding `system:auth-delegator` belum ada: `external-secrets/vault-token-reviewer` dan `vault-token-reviewer-auth-delegator`.
- Field `token_reviewer_jwt_set: false` — Vault tidak bisa verify TokenReview ke Kubernetes API. Set `token_reviewer_jwt` secara eksplisit (lihat [Setup Vault](02-setup-vault.md) langkah 4).
- `audience` di Vault role tidak kosong tetapi audience token actual berbeda. Untuk Docker Desktop, token audience adalah `https://kubernetes.default.svc.cluster.local` bukan string `vault`.

Cek config Vault dari dalam container:

```bash
docker exec vault-local sh -lc \
  'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true VAULT_TOKEN=<token> \
  vault read auth/kubernetes-local/config'
```

Test login direct dari host:

```bash
TOKEN=$(kubectl -n external-secrets create token external-secrets --duration=10m)
curl -sk --request POST \
  --data "{\"role\":\"external-secrets\",\"jwt\":\"$TOKEN\"}" \
  https://localhost:8200/v1/auth/kubernetes-local/login
```

Berhasil jika ada `client_token` di response.

Perbaikan cepat: ulangi [Setup Vault](02-setup-vault.md) langkah 3-7. Setelah itu trigger ulang reconcile ESO:

```bash
kubectl annotate clustersecretstore databases force-sync="$(date +%s)" --overwrite
kubectl annotate clustersecretstore prohukum-apps force-sync="$(date +%s)" --overwrite
kubectl -n external-secrets rollout restart deployment/external-secrets
```

---

**CRD exists and cannot be imported**

Error:
```text
CustomResourceDefinition "..." exists and cannot be imported into the current release
```

Solusi: deploy chart tanpa menginstall CRDs:

```bash
helm upgrade --install external-secrets charts/external-secrets \
  -n external-secrets \
  --create-namespace \
  -f charts/external-secrets/values.production.yaml \
  --set external-secrets.installCRDs=false
```

CRD sudah ada di cluster; chart hanya perlu deploy operator dan bootstrap resources.

---

**Helm uninstall stuck atau invalid ownership metadata**

Error saat install/upgrade root chart:

```text
invalid ownership metadata; annotation validation error: key "meta.helm.sh/release-name" must equal...
```

Jika release lama sudah dihapus tetapi `Application` Argo CD masih `Terminating`, biasanya finalizer Argo CD tersangkut karena `AppProject` sudah ikut terhapus. Cek:

```bash
helm list -n argocd -a
kubectl -n argocd get application -o custom-columns=NAME:.metadata.name,DEL:.metadata.deletionTimestamp,FINALIZERS:.metadata.finalizers
kubectl -n argocd get appproject
```

Lepas finalizer pada `Application` yang stuck:

```bash
kubectl -n argocd patch application external-secrets \
  --type=json \
  -p='[{"op":"remove","path":"/metadata/finalizers"}]'
```

Install ulang root chart dan ambil alih resource existing:

```bash
helm upgrade --install kubernetes-helm-devops charts/argocd-apps \
  -n argocd \
  -f charts/argocd-apps/values.production.yaml \
  --take-ownership
```

---

**Argo CD sync error: SSH agent**

Error:
```text
failed to list refs: error creating SSH agent: "SSH agent requested but SSH_AUTH_SOCK not-specified"
```

Solusi: daftarkan repository SSH credential ke Argo CD:

```bash
kubectl -n argocd create secret generic repo-devops \
  --from-literal=type=git \
  --from-literal=url=git@github.com:ersaazis/kubernetes-helm-devops.git \
  --from-file=sshPrivateKey=$HOME/.ssh/id_ed25519 \
  --dry-run=client -o yaml | \
kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | \
kubectl apply -f -
```

Refresh Application setelah secret terdaftar:

```bash
kubectl -n argocd annotate application external-secrets \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

**ClusterSecretStore status InvalidProviderConfig: TLS error**

Error:
```text
unable to create client: couldn't create vault client: failed to parse CA bundle
```

Penyebab: nilai `caBundle` di Helm bukan base64 valid atau tidak sesuai CA Vault HTTPS.

Cara mendapatkan CA Vault yang benar:

```bash
openssl s_client -connect localhost:8200 -showcerts </dev/null 2>/dev/null | \
  awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' | \
  base64 -w0
```

Masukkan hasil itu ke `vaultStore.provider.caBundle` dan `vaultStoreApps.provider.caBundle` di `values.production.yaml`.

---

**ClusterSecretStore status: kahuripan/connectivity error dari pod ESO ke Vault**

Cek apakah `host.docker.internal` bisa direach dari pod:

```bash
kubectl -n external-secrets run tmp-shell --rm -it --image=curlimages/curl:latest \
  --restart=Never -- curl -sk https://host.docker.internal:8200/v1/sys/health
```

Pastikan server Vault diisi dengan URL yang reachable dari dalam cluster, bukan `localhost`.

## Validasi Chart Lokal

Jalankan script validasi sebelum push ke Git:

```bash
./scripts/validate-charts.sh
```

Render individual untuk debug:

```bash
helm template external-secrets charts/external-secrets \
  -n external-secrets \
  -f charts/external-secrets/values.production.yaml \
  --set external-secrets.installCRDs=false

helm template kubernetes-helm-devops charts/argocd-apps \
  -n argocd \
  -f charts/argocd-apps/values.production.yaml
```
