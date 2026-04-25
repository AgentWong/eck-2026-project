---
description: 'Run comprehensive health checks on the local ECK stack'
---

Run a comprehensive verification of the local ECK 2026 stack and produce a status report.

## Checks to Run

### Cluster Health
- `kubectl get nodes` — all Ready?
- `kubectl top nodes` — memory usage under 80%?

### Component Health
- `helm list -A` — all releases deployed?
- `kubectl get clusterissuer selfsigned-issuer` — Ready?
- `istioctl analyze` — no errors?
- `kubectl get pods -l app.kubernetes.io/name=kiali -n istio-system` — Running?
- `kubectl get pods -l app.kubernetes.io/name=prometheus -n istio-system` — Running?
- `kubectl get elasticsearch -n elastic` — green?
- `kubectl get kibana -n elastic` — green?
- `kubectl get keycloak -n keycloak` — exists?
- `kubectl get pods -A` — all Running or Completed?

### Network Policies
- `kubectl get networkpolicies -n argocd` — default-deny + allow rules present?
- `kubectl get networkpolicies -n elastic` — default-deny + allow rules present?
- `kubectl get networkpolicies -n istio-system` — default-deny + allow rules present?
- `kubectl get networkpolicies -n keycloak` — default-deny + allow rules present?

### Credentials (verify secrets exist)
- ArgoCD: `argocd-initial-admin-secret` in namespace `argocd`
- Elasticsearch: `elasticsearch-es-elastic-user` in namespace `elastic`
- Keycloak: `keycloak-initial-admin` in namespace `keycloak`

## Output Format

Produce a summary table:

| Component | Status | Details |
|-----------|--------|---------|
| ... | PASS/FAIL | ... |

End with overall verdict: ALL PASS or list of failures.
