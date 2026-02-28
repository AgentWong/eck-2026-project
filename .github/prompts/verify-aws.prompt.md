---
description: 'Verify AWS EKS deployment health and check for cost exposure'
agent: 'AWS EKS Tester'
tools:
  ['execute', 'read', 'agent', 'edit', 'search', 'todo']
---

Run comprehensive verification of the AWS ECK 2026 deployment.

## Infrastructure Checks

- `aws eks describe-cluster --name eck-2026-dev --query 'cluster.status'` — ACTIVE?
- `kubectl get nodes` — all Ready? Correct instance types?
- Terraform drift check (should show "No changes"):
  - `cd terraform/environments/dev/vpc && terragrunt plan`
  - `cd terraform/environments/dev/eks && terragrunt plan`

## Application Checks

- `kubectl get applications -n argocd` — all Synced + Healthy?
- `kubectl get pods -A` — all Running/Completed?
- `kubectl get elasticsearch -n elastic` — green?
- `kubectl get kibana -n elastic` — green?
- `kubectl get keycloak -n keycloak` — exists?
- `kubectl get pods -l app.kubernetes.io/name=kiali -n istio-system` — Running?

## Application Health Checks

These API-level checks verify that services are functional end-to-end, not just that pods are running.

### Elasticsearch

```bash
ES_PASS=$(kubectl get secret elasticsearch-es-elastic-user -n elastic -o jsonpath='{.data.elastic}' | base64 -d)
# Cluster health — expect green
kubectl exec -n elastic deployment/kibana-kb -- curl -sk -u "elastic:${ES_PASS}" \
  https://elasticsearch-es-http.elastic.svc:9200/_cluster/health | jq '{status,number_of_nodes,active_shards}'
```

### Kibana

```bash
# Kibana status API — expect overall.state = "green" or "available"
kubectl exec -n elastic deployment/kibana-kb -- curl -sk \
  http://localhost:5601/api/status | jq '{name: .name, status: .status.overall.level}'
```

### Fleet Server enrollment

```bash
# Fleet agents enrolled and online — expect fleet-server and elastic-agent both "online"
KB_PASS=$(kubectl get secret elasticsearch-es-elastic-user -n elastic -o jsonpath='{.data.elastic}' | base64 -d)
kubectl exec -n elastic deployment/kibana-kb -- curl -sk -u "elastic:${KB_PASS}" \
  http://localhost:5601/api/fleet/agents?perPage=50 \
  -H 'kbn-xsrf: true' | jq '[.items[] | {id, status, policy_id}]'
```

### Kibana receiving logs from Elastic Agent

```bash
# Confirm log documents are flowing into Elasticsearch from elastic-agent
kubectl exec -n elastic deployment/kibana-kb -- curl -sk -u "elastic:${ES_PASS}" \
  'https://elasticsearch-es-http.elastic.svc:9200/logs-*/_count' | jq '{count}'
```

### Keycloak OIDC endpoint

```bash
# Keycloak OIDC discovery — expect issuer field present
kubectl exec -n keycloak deployment/keycloak -- curl -sk \
  https://keycloak-service.keycloak.svc:8443/realms/eck-2026/.well-known/openid-configuration \
  | jq '{issuer, authorization_endpoint}'
```

### Kiali — Istio traffic graph

```bash
# Kiali health endpoint — expect globalStatus healthy
kubectl exec -n istio-system deployment/kiali -- curl -sk \
  http://localhost:20001/api/namespaces/elastic/graph?duration=60s\&graphType=workload \
  | jq '{duration: .graphMeta.timestamp}' 2>/dev/null || \
  kubectl exec -n istio-system deployment/kiali -- curl -sk \
  http://localhost:20001/healthz/ready
```

### Istio mesh analysis

```bash
# No errors in mesh configuration
istioctl analyze -n elastic
```

## Networking Checks

- `kubectl get svc -A --field-selector spec.type=LoadBalancer` — external IPs assigned?
- `kubectl get networkpolicies -A` — all policies present?

## Cost Exposure Check

```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType}'
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" \
  --query 'NatGateways[].{ID:NatGatewayId,State:State}'
```

## Remediation

If any checks fail, attempt to fix them before producing the final summary. Common fixes:

### Keycloak CRD not found / sync failed

The Keycloak Operator is installed via raw manifests (no Helm chart). If missing:

```bash
# Install CRDs
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml

# Install Operator (create namespace if needed)
kubectl create namespace keycloak 2>/dev/null || true
kubectl -n keycloak apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/kubernetes.yml
kubectl wait --for=condition=Ready pods --all -n keycloak --timeout=90s
```

### ArgoCD app stuck OutOfSync after retries exhausted

Force a re-sync by patching the application with a new sync operation:

```bash
kubectl patch application <APP_NAME> -n argocd --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

Wait 15-30s and re-check. This is often needed after fixing a root cause (e.g., missing CRDs or namespaces) when automated retries are exhausted.

### Elastic Agent degraded

Check agent logs for the specific error. A single degraded agent on a fresh deployment often self-resolves within a few minutes as Fleet policies propagate.

After remediation, re-run the relevant checks to confirm the fix before producing the summary.

## Output Format

Produce a summary table:

| Component | Status | Details |
|-----------|--------|---------|
| EKS Cluster | PASS/FAIL | Node count, instance types |
| ArgoCD Apps | PASS/FAIL | All Synced + Healthy |
| Elasticsearch | PASS/FAIL | CRD health + API cluster status (green/yellow/red) |
| Kibana | PASS/FAIL | CRD health + API status level |
| Fleet Server | PASS/FAIL | Agent enrolled and online |
| Elastic Agent | PASS/FAIL | Agents online + log documents flowing |
| Keycloak | PASS/FAIL | CRD exists + OIDC discovery endpoint reachable |
| Kiali | PASS/FAIL | Pod running + traffic graph API responsive |
| Istio mesh | PASS/FAIL | `istioctl analyze` — no errors |
| Network Policies | PASS/FAIL | Policies present in all namespaces |
| Load Balancer IPs | PASS/FAIL | External IPs assigned |
| Cost exposure | INFO | Running EC2 instances, NAT gateways |

End with:
- Overall verdict (ALL PASS or list of failures)
- **Cost reminder**: Estimated ~$2.30/8-hr day while resources are running. Run teardown when done.
