# Install Argo CD

Panduan instalasi Argo CD ke cluster Kubernetes sebelum kita menerapkan `Application` GitOps.

## 1. Install via Manifest

Buat namespace `argocd` dan apply manifest resmi Argo CD:

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/master/manifests/install.yaml
```

Tunggu sampai semua pods running:

```bash
kubectl -n argocd get pods
```

## 2. Akses UI

Buka port-forward dari laptop ke service Argo CD server:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Akses di browser via: `https://localhost:8080`

## 3. Login Initial Admin

Ambil password initial untuk user `admin`:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Login ke UI dan ganti password dari tab User Info.

## 4. Konfigurasi Repository Credential (Opsional)

Jika repository `kubernetes-helm-devops` diatur sebagai private, Argo CD butuh akses SSH atau HTTPS.

Contoh dengan SSH key deploy:

```bash
kubectl -n argocd create secret generic repo-devops \
  --from-literal=type=git \
  --from-literal=url=git@github.com:ersaazis/kubernetes-helm-devops.git \
  --from-file=sshPrivateKey=$HOME/.ssh/id_ed25519 \
  --dry-run=client -o yaml | \
kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | \
kubectl apply -f -
```

Pastikan url sama persis dengan yang ada di `charts/argocd-apps/values.yaml`.
