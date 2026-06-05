# Deploy Argo CD Apps

Panduan ini menjelaskan cara menginstall chart `argocd-apps` yang otomatis membuat `AppProject` dan kumpulan `Application` untuk platform ini.

Argo CD akan melakukan rekonsiliasi chart infrastruktur dan platform sesuai urutan `sync-wave` (ESO di `-10`, lain-lain setelahnya).

## 1. Pastikan Nilai Repository Sesuai

Chart `argocd-apps` mengasumsikan URL repo yang persis sesuai yang terdaftar di secret credential Argo CD (lihat [Install Argo CD](01-install-argocd.md)).

Pastikan `argo.repoURL` di `charts/argocd-apps/values.yaml` valid, misal:

```yaml
argo:
  repoURL: 'git@github.com:ersaazis/kubernetes-helm-devops.git'
  targetRevision: main
```

## 2. Pastikan Overlay Tersedia di Git

Argo CD Application `external-secrets` dalam repo ini mewajibkan dua file `valueFiles`:

```yaml
applications:
  external-secrets:
    valueFiles:
      - values.production.yaml
      - values.argocd.production.yaml
```

File `charts/external-secrets/values.argocd.production.yaml` wajib ada, direpresentasikan sebagai override spesifik environment repo (bahkan jika isinya kosong).

## 3. Pre-Apply CRDs External Secrets

Secara default `values.production.yaml` pada `external-secrets` mengeset `installCRDs: false` untuk Argo CD flow. Jika cluster belum punya CRD ESO, Argo CD akan gagal mensync instance `ClusterSecretStore`.

Cara manual inject CRDs dari chart dependency yang sudah vendored:

```bash
helm show crds charts/external-secrets/charts/external-secrets-2.5.0.tgz | kubectl apply -f -
```

Jika file dependency belum ada, build dulu:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets
helm dependency build charts/external-secrets
```

Setelah CRD tersedia, Argo CD dapat mensync chart `external-secrets` dengan `external-secrets.installCRDs=false` tanpa konflik ownership CRD.

## 4. Install App of Apps

Install root chart menggunakan Helm:

```bash
helm upgrade --install kubernetes-helm-devops charts/argocd-apps \
  -n argocd \
  -f charts/argocd-apps/values.production.yaml
```

## 5. Sync Argo CD

Cek apakah `Application` sudah muncul:

```bash
kubectl -n argocd get application
```

Harusnya terlihat status sync `Unknown` atau `Synced`. Jika status `Unknown`, biasanya Argo CD memerlukan sinkronisasi manual pertama kali atau cache belum update.

Force hard refresh:

```bash
kubectl -n argocd annotate application external-secrets \
  argocd.argoproj.io/refresh=hard \
  --overwrite
```

Jika status sinkronisasi masih error `ComparisonError` dengan `failed to list refs: error creating SSH agent`, kembali ke Step 4 pada [Install Argo CD](01-install-argocd.md) untuk mendaftarkan kredensial repository.
