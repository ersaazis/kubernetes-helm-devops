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

helm template platform-devops-prod charts/argocd-apps \
  -n argocd \
  -f charts/argocd-apps/values.production.yaml
```
