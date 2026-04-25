---
description: 'Tear down the complete local ECK stack in correct reverse order'
---

Tear down the entire ECK 2026 stack from the local Rancher Desktop K3s cluster.

## Procedure

1. Read `docs/teardown-and-rebuild.md` section "Local Stack: Complete Teardown" for exact commands
2. Teardown in **strict reverse dependency order**:
   - Network Policies → Keycloak (realm + instance + operator + CRDs) → Elastic Stack + ECK Operator → Prometheus + Kiali + Istio (istiod + base) → cert-manager (ClusterIssuer + helm release) → ArgoCD
3. Wait for resources to terminate between steps (especially Elasticsearch pods — can take 60s+)
4. Run the clean state verification

## Post-Teardown Verification

Confirm only system namespaces remain:

```
kubectl get namespaces
kubectl get crds | grep -E 'cert-manager|istio|kiali|elastic|keycloak|argoproj'
helm list -A
```

Report what was removed and whether the cluster is clean.
