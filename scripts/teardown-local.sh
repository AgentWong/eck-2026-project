#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.rd/bin:$PATH"
LOG="/tmp/teardown-local.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== ECK 2026 Local Teardown ==="
echo "Started: $(date)"

# Step 1: Keycloak Operator CRDs and resources (not managed by ArgoCD/Helm)
echo ""
echo "[Step 1] Deleting Keycloak Operator and CRDs..."
kubectl -n keycloak delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/kubernetes.yml --ignore-not-found || true
kubectl delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml --ignore-not-found || true
kubectl delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml --ignore-not-found || true
echo "[Step 1] Done"

# Step 2: Delete application namespaces (removes all lingering resources + PVCs)
echo ""
echo "[Step 2] Deleting application namespaces..."
for ns in elastic keycloak elastic-system istio-system cert-manager; do
  kubectl delete namespace "$ns" --ignore-not-found || true
done
echo "[Step 2] Delete commands issued"

# Step 3: Wait for Elasticsearch (heaviest) to fully terminate
echo ""
echo "[Step 3] Waiting for elastic namespace to fully terminate (up to 180s)..."
kubectl wait --for=delete namespace/elastic --timeout=180s || true
echo "[Step 3] elastic namespace gone"

# Step 4: Wait for remaining namespaces
echo ""
echo "[Step 4] Waiting for remaining namespaces to terminate..."
for ns in keycloak elastic-system istio-system cert-manager; do
  kubectl wait --for=delete namespace/"$ns" --timeout=120s || true
  echo "  namespace/$ns terminated"
done
echo "[Step 4] Done"

# Step 5: Uninstall ArgoCD Helm release
echo ""
echo "[Step 5] Uninstalling ArgoCD Helm release..."
helm uninstall argocd -n argocd --ignore-not-found 2>/dev/null || helm uninstall argocd -n argocd || true
echo "[Step 5] Done"

# Step 6: Delete ArgoCD namespace
echo ""
echo "[Step 6] Deleting argocd namespace..."
kubectl delete namespace argocd --ignore-not-found || true
kubectl wait --for=delete namespace/argocd --timeout=120s || true
echo "[Step 6] Done"

echo ""
echo "=== TEARDOWN STEPS COMPLETE ==="
echo "Finished: $(date)"
echo ""
echo "=== FINAL VERIFICATION ==="
echo "--- Namespaces ---"
kubectl get namespaces
echo ""
echo "--- Lingering CRDs ---"
kubectl get crds 2>/dev/null | grep -E 'cert-manager|istio|kiali|elastic|keycloak|argoproj' || echo "(none found)"
echo ""
echo "--- Helm releases ---"
helm list -A
echo ""
echo "--- PVCs ---"
kubectl get pvc -A 2>/dev/null || echo "(none)"
echo ""
echo "Done."
