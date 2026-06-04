# Setup Vault

Dokumen ini menyiapkan Vault agar External Secrets Operator dapat login memakai Kubernetes auth dan membaca KV v2 mount `databases` serta `prohukum-apps`.

Contoh di bawah memakai auth path final repo ini: `kubernetes-local`.

## 1. Siapkan Variabel Lokal

```bash
export VAULT_ADDR=https://localhost:8200
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN='<vault-admin-token>'
export K8S_AUTH_PATH=kubernetes-local
```

Jangan commit nilai `VAULT_TOKEN`.

Jika Vault CLI hanya tersedia di container, masuk dulu:

```bash
docker exec -it vault-local sh
```

## 2. Ambil Kubernetes API Host dan CA

Untuk Docker Desktop cluster lokal, API server pada kubeconfig biasanya terlihat sebagai `127.0.0.1:<port>`. Dari container Vault, gunakan hostname yang valid di sertifikat API server:

```bash
export KUBERNETES_HOST=https://desktop-control-plane:61829
```

Ambil CA Kubernetes API dari kubeconfig:

```bash
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/k8s-ca.crt
```

Pastikan container Vault bisa resolve host tersebut. Untuk Docker Desktop, mapping umum:

```text
192.168.65.254 desktop-control-plane
```

## 3. Buat Reviewer Service Account

Vault membutuhkan JWT reviewer untuk memanggil Kubernetes `TokenReview` API. Gunakan service account khusus agar tidak bergantung pada service account ESO yang baru dibuat saat chart disync.

```bash
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

kubectl -n external-secrets create serviceaccount vault-token-reviewer \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create clusterrolebinding vault-token-reviewer-auth-delegator \
  --clusterrole=system:auth-delegator \
  --serviceaccount=external-secrets:vault-token-reviewer \
  --dry-run=client -o yaml | kubectl apply -f -
```

Buat reviewer JWT. Untuk local lab, token 1 tahun cukup praktis; untuk production gunakan lifecycle/rotation yang dikelola.

```bash
kubectl -n external-secrets create token vault-token-reviewer --duration=8760h > /tmp/vault-token-reviewer.jwt
```

## 4. Enable dan Configure Kubernetes Auth

Enable auth path jika belum ada:

```bash
vault auth enable -path="$K8S_AUTH_PATH" kubernetes
```

Configure Vault Kubernetes auth:

```bash
vault write "auth/$K8S_AUTH_PATH/config" \
  kubernetes_host="$KUBERNETES_HOST" \
  kubernetes_ca_cert=@/tmp/k8s-ca.crt \
  token_reviewer_jwt=@/tmp/vault-token-reviewer.jwt \
  disable_local_ca_jwt=false
```

Expected check:

```bash
vault read "auth/$K8S_AUTH_PATH/config"
```

Pastikan nilainya:

```text
kubernetes_host         https://desktop-control-plane:61829
token_reviewer_jwt_set  true
disable_local_ca_jwt    false
```

## 5. Enable KV v2 Mounts

```bash
vault secrets enable -path=databases kv-v2
vault secrets enable -path=prohukum-apps kv-v2
```

Jika mount sudah ada, command akan error `path is already in use`; itu aman.

## 6. Buat Policy External Secrets

Buat file policy lokal:

```bash
cat > /tmp/external-secrets-policy.hcl <<'EOF'
path "databases/data/*" {
  capabilities = ["read"]
}

path "databases/metadata/*" {
  capabilities = ["read", "list"]
}

path "prohukum-apps/data/*" {
  capabilities = ["read"]
}

path "prohukum-apps/metadata/*" {
  capabilities = ["read", "list"]
}
EOF
```

Apply ke Vault:

```bash
vault policy write external-secrets /tmp/external-secrets-policy.hcl
```

## 7. Buat Role untuk ESO

Role ini mengizinkan service account runtime ESO `external-secrets/external-secrets` mengambil token Vault dengan policy `external-secrets`.

```bash
vault write "auth/$K8S_AUTH_PATH/role/external-secrets" \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h
```

Audience dikosongkan. Token service account Docker Desktop biasanya memakai audience `https://kubernetes.default.svc.cluster.local`; jika Vault role diisi audience yang berbeda, login akan gagal `403 permission denied`.

## 8. Validasi Setelah ESO Terinstall

Setelah `charts/external-secrets` disync oleh Argo CD, test login dengan service account ESO:

```bash
TOKEN=$(kubectl -n external-secrets create token external-secrets --duration=10m)

curl -sk --request POST \
  --data "{\"role\":\"external-secrets\",\"jwt\":\"$TOKEN\"}" \
  "$VAULT_ADDR/v1/auth/$K8S_AUTH_PATH/login"
```

Berhasil jika response berisi `client_token`.

## Catatan CA

- `kubernetes_ca_cert` adalah CA Kubernetes API untuk Vault memvalidasi API server.
- `vaultStore.provider.caBundle` di Helm adalah CA Vault HTTPS untuk ESO memvalidasi server Vault.
- Jangan tertukar; keduanya sertifikat berbeda.
