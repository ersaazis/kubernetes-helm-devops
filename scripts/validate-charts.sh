#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${ROOT_DIR}"

APP_CHARTS=()
ARGOCD_APPS_CHART="charts/argocd-apps"
TEMP_KUBECONFIG=""

require_helm() {
  if ! command -v helm >/dev/null 2>&1; then
    echo "helm not found in PATH" >&2
    exit 1
  fi
}

prepare_helm_env() {
  if [[ -n "${KUBECONFIG:-}" ]]; then
    return
  fi

  TEMP_KUBECONFIG=$(mktemp)
  chmod 600 "${TEMP_KUBECONFIG}"
  cat > "${TEMP_KUBECONFIG}" <<'EOF'
apiVersion: v1
kind: Config
clusters: []
contexts: []
current-context: ""
users: []
EOF
  export KUBECONFIG="${TEMP_KUBECONFIG}"
}

cleanup() {
  if [[ -n "${TEMP_KUBECONFIG}" ]]; then
    rm -f "${TEMP_KUBECONFIG}"
  fi
}

generate_app_smoke_overrides() {
  local values_file=$1
  local output_file=$2

  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function sanitize(s, out) {
      out = tolower(s)
      gsub(/[^a-z0-9]+/, "-", out)
      gsub(/^-+/, "", out)
      gsub(/-+$/, "", out)
      return out
    }
    BEGIN {
      print "services:"
    }
    /^services:[[:space:]]*$/ {
      in_services = 1
      next
    }
    in_services && /^[^[:space:]]/ {
      in_services = 0
    }
    !in_services {
      next
    }
    /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ {
      current = $0
      sub(/^  /, "", current)
      sub(/:[[:space:]]*$/, "", current)
      if (!(current in seen)) {
        seen[current] = 1
        order[++count] = current
      }
      next
    }
    current != "" && /- host:[[:space:]]*/ {
      host = $0
      sub(/.*- host:[[:space:]]*/, "", host)
      gsub(/"/, "", host)
      host = trim(host)
      if (host != "") {
        host_count[current]++
        hosts[current, host_count[current]] = host
      }
    }
    END {
      for (i = 1; i <= count; i++) {
        svc = order[i]
        repo = sanitize(svc)
        print "  " svc ":"
        print "    image:"
        print "      repository: ghcr.io/production/" repo
        print "      tag: \"2026.05.28.1\""
        if (host_count[svc] > 0) {
          print "    ingress:"
          print "      tls:"
          print "        - secretName: " repo "-tls"
          print "          hosts:"
          for (j = 1; j <= host_count[svc]; j++) {
            print "            - " hosts[svc, j]
          }
        }
      }
    }
  ' "${values_file}" > "${output_file}"
}

run_chart_checks() {
  local chart=$1
  local chart_name
  local values_file="${chart}/values.yaml"

  chart_name=$(basename "${chart}")

  echo "==> ${chart_name}"

  if grep -q '^dependencies:' "${chart}/Chart.yaml"; then
    helm dependency update "${chart}" --skip-refresh >/dev/null
  fi

  helm lint "${chart}"

  if [[ -f "${values_file}" ]]; then
    helm template test "${chart}" -f "${values_file}" >/dev/null
  fi

  if [[ -f "${chart}/values.production.yaml" ]]; then
    if [[ " ${APP_CHARTS[*]} " == *" ${chart} "* ]]; then
      local smoke_override
      smoke_override=$(mktemp)
      generate_app_smoke_overrides "${values_file}" "${smoke_override}"
      helm template test "${chart}" -f "${chart}/values.production.yaml" -f "${smoke_override}" >/dev/null
      rm -f "${smoke_override}"
    else
      helm template test "${chart}" -f "${chart}/values.production.yaml" >/dev/null
    fi
  fi
}

run_argocd_apps_checks() {
  local chart=$1
  local render_output
  local smoke_values
  local missing_revision_values
  local missing_overlay_values
  local app_count
  local project_count

  echo "==> $(basename "${chart}")"

  smoke_values=$(mktemp)
  render_output=$(mktemp)
  cat > "${smoke_values}" <<EOF
argo:
  repoURL: https://github.com/acme/kubernetes-helm-config.git
  targetRevision: main
EOF

  helm lint "${chart}" -f "${chart}/values.production.yaml" -f "${smoke_values}"

  helm template smoke "${chart}" -f "${chart}/values.production.yaml" -f "${smoke_values}" > "${render_output}"

  app_count=$(grep -c '^kind: Application$' "${render_output}" || true)
  project_count=$(grep -c '^kind: AppProject$' "${render_output}" || true)

  if [[ "${app_count}" -ne 1 ]]; then
    echo "argocd-apps: expected 1 Application resources, got ${app_count}" >&2
    exit 1
  fi

  if [[ "${project_count}" -ne 1 ]]; then
    echo "argocd-apps: expected 1 AppProject resource, got ${project_count}" >&2
    exit 1
  fi

  if grep -q 'path: charts/app-template' "${render_output}"; then
    echo "argocd-apps: app-template must not be rendered as Argo CD Application" >&2
    exit 1
  fi

  grep -q 'argocd.argoproj.io/sync-wave: "-10"' "${render_output}" || {
    echo 'argocd-apps: expected sync wave -10 for bootstrap applications' >&2
    exit 1
  }

  if helm template invalid-repo "${chart}" -f "${chart}/values.production.yaml" --set argo.repoURL="" >/dev/null 2>&1; then
    echo "argocd-apps: expected validation failure when argo.repoURL is not set" >&2
    exit 1
  fi

  missing_revision_values=$(mktemp)
  cat > "${missing_revision_values}" <<EOF
argo:
  repoURL: https://github.com/acme/kubernetes-helm-config.git
  targetRevision: ''
EOF

  if helm template invalid-revision "${chart}" -f "${chart}/values.production.yaml" -f "${missing_revision_values}" >/dev/null 2>&1; then
    echo "argocd-apps: expected validation failure when argo.targetRevision is empty" >&2
    exit 1
  fi

  missing_overlay_values=$(mktemp)
  cat > "${missing_overlay_values}" <<EOF
argo:
  repoURL: https://github.com/acme/kubernetes-helm-config.git
  targetRevision: main
applications:
  external-secrets:
    valueFiles:
      - values.production.yaml
EOF

  if helm template invalid-overlay "${chart}" -f "${chart}/values.production.yaml" -f "${missing_overlay_values}" >/dev/null 2>&1; then
    echo "argocd-apps: expected validation failure when required ArgoCD overlay value file is missing" >&2
    exit 1
  fi

  rm -f "${smoke_values}" "${render_output}" "${missing_revision_values}" "${missing_overlay_values}"
}

require_helm
prepare_helm_env
trap cleanup EXIT

for chart in charts/*; do
  [[ -f "${chart}/Chart.yaml" ]] || continue
  if [[ "${chart}" == "${ARGOCD_APPS_CHART}" ]]; then
    run_argocd_apps_checks "${chart}"
  else
    run_chart_checks "${chart}"
  fi
done

echo "All chart validation checks passed"
