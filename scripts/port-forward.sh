#!/usr/bin/env bash
set -euo pipefail

# port-forward.sh — Quick access to local services via kubectl port-forward

usage() {
  echo "Usage: $0 <service>"
  echo ""
  echo "Services:"
  echo "  argocd     - ArgoCD UI         (localhost:8080)"
  echo "  kibana     - Kibana UI          (localhost:5601)"
  echo "  keycloak   - Keycloak Console   (localhost:8443)"
  echo "  es         - Elasticsearch API  (localhost:9200)"
  echo "  kiali      - Kiali UI           (localhost:20001)"
  echo "  all        - All of the above"
  exit 1
}

# Preflight: verify the cluster is reachable before doing anything
preflight_check() {
  if ! kubectl cluster-info --request-timeout=5s &>/dev/null; then
    echo "✗ Cannot connect to Kubernetes cluster."
    echo ""
    echo "  Possible causes:"
    echo "    • Rancher Desktop is not running"
    echo "    • The Lima SSH tunnel dropped (port 6443 not forwarded)"
    echo "    • kubeconfig is pointing at the wrong server or has a stale CA cert"
    echo ""
    echo "  Quick fixes:"
    echo "    1. Open Rancher Desktop and wait for Kubernetes to show 'Running'"
    echo "    2. Restore the SSH tunnel:"
    echo "       ssh -O forward -S \"\$HOME/Library/Application Support/rancher-desktop/lima/0/ssh.sock\" -L 6443:127.0.0.1:6443 dummy"
    echo "    3. Reset kubeconfig server address:"
    echo "       kubectl config set-cluster rancher-desktop --server=https://127.0.0.1:6443"
    echo ""
    exit 1
  fi
}

check_service() {
  local svc="$1" ns="$2"
  local output
  output=$(kubectl get svc "$svc" -n "$ns" 2>&1)
  if [ $? -ne 0 ]; then
    if echo "$output" | grep -qi "connect\|tls\|timeout\|refused"; then
      echo "  ✗ Cannot reach cluster API — run '$0' again after fixing connectivity"
      exit 1
    fi
    echo "  ⚠ Service $svc not found in namespace $ns — skipping"
    return 1
  fi
  # Check that at least one endpoint is ready
  local ready
  ready=$(kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
  if [ -z "$ready" ]; then
    echo "  ⚠ Service $svc has no ready endpoints — pod may not be running"
    return 1
  fi
  return 0
}

forward_argocd() {
  echo "→ ArgoCD UI at https://localhost:8080"
  check_service argocd-server argocd || return 0
  kill_stale 8080
  kubectl port-forward svc/argocd-server -n argocd 8080:443 &
}

forward_kibana() {
  echo "→ Kibana at https://localhost:5601"
  check_service kibana-kb-http elastic || return 0
  kill_stale 5601
  kubectl port-forward svc/kibana-kb-http -n elastic 5601:5601 &
}

forward_keycloak() {
  echo "→ Keycloak at https://localhost:8443"
  check_service keycloak-service keycloak || return 0
  kill_stale 8443
  kubectl port-forward svc/keycloak-service -n keycloak 8443:8443 &
}

forward_es() {
  echo "→ Elasticsearch at https://localhost:9200"
  check_service elasticsearch-es-http elastic || return 0
  kill_stale 9200
  kubectl port-forward svc/elasticsearch-es-http -n elastic 9200:9200 &
}

forward_kiali() {
  echo "→ Kiali at https://localhost:20001"
  check_service kiali istio-system || return 0
  kill_stale 20001
  kubectl port-forward svc/kiali -n istio-system 20001:20001 &
}

cleanup() {
  echo ""
  echo "Stopping port-forwards..."
  kill $(jobs -p) 2>/dev/null
  exit 0
}

trap cleanup SIGINT SIGTERM

# Kill any leftover port-forward processes from previous runs
kill_stale() {
  local port="$1"
  local pids
  pids=$(lsof -ti :"$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "  ⚠ Killing stale process on port $port"
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
  fi
}

[ $# -eq 0 ] && usage

preflight_check

case "$1" in
  argocd)   forward_argocd ;;
  kibana)   forward_kibana ;;
  keycloak) forward_keycloak ;;
  es)       forward_es ;;
  kiali)    forward_kiali ;;
  all)
    forward_argocd
    forward_kibana
    forward_keycloak
    forward_es
    forward_kiali
    ;;
  *) usage ;;
esac

# Check if any port-forwards are actually running
if [ -z "$(jobs -p 2>/dev/null)" ]; then
  echo ""
  echo "No port-forwards started. Check that services are deployed and pods are ready."
  exit 1
fi

echo ""
echo "Press Ctrl+C to stop all port-forwards."
wait
