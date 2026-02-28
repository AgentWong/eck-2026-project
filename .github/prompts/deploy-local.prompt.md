---
description: 'Deploy the full ECK stack to local Rancher Desktop K3s'
agent: 'Local K8s Tester'
tools:
  ['execute', 'read', 'agent', 'edit', 'search', 'todo']
---

Deploy the complete ECK 2026 stack to the local Rancher Desktop K3s cluster.

## Procedure

1. Run `./scripts/setup-local.sh` to verify all prerequisites are installed
2. Read `docs/teardown-and-rebuild.md` section "Local Stack: Full Rebuild" for exact commands
3. Deploy each component in sync-wave order, waiting for readiness between steps:
   - ArgoCD → cert-manager + ClusterIssuer → Istio base → Istiod → Kiali + Prometheus → ECK Operator → Elastic Stack → Monitoring (kube-state-metrics, Fleet Server, Elastic Agent) → Keycloak → Network Policies
4. After all components are deployed, run the full verification checklist
5. Report the final state as a summary table

## Rules

- If any step fails, **stop and report the error**. Do not continue past a failed step.
- Use `kubectl wait` with appropriate `--timeout` flags between steps.
- The `elastic` namespace must have `istio-injection=enabled` label before deploying Elasticsearch/Kibana.
- After deploying the Elastic Stack and monitoring components, **restart pods** in the `elastic` namespace so Istio sidecars are injected. The Elastic Agent DaemonSet is excluded via annotation (`sidecar.istio.io/inject: "false"`) because it uses `hostNetwork`.
- Do not skip the realm import step for Keycloak — wait for the import job to complete.
