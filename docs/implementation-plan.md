# ECK 2026 Project - Implementation Plan

> **Status as of 2026-02-25:** All phases (0–9) are **complete**. Local K3s and AWS EKS deployments are both tested and working.

## Context

You previously deployed a basic Elastic Stack on Kubernetes using Terragrunt + kubectl/Terraform providers and want to redo it properly — well-planned, well-tested, and professionally showcased. This plan covers the full journey: local development on Rancher Desktop through to AWS EKS deployment, using ArgoCD for GitOps, with Istio, Keycloak, cert-manager, and Network Policies.

## Current System State

**Installed**: Terraform v1.14.3, Terragrunt v0.96.1, Git, GitHub CLI (not authenticated), Trivy
**Available via Rancher Desktop** (`~/.rd/bin/`, but NOT on PATH): kubectl v1.34.3, helm v4.0.5, docker, nerdctl
**Not installed**: argocd CLI, istioctl, AWS CLI
**Rancher Desktop cluster**: K3s v1.34.3, single node with 10GB RAM / 8 vCPUs, `local-path` default StorageClass, Traefik pre-installed. Cluster is clean (only system pods).

---

## Key Architectural Decisions

### 1. Mono-repo (single private GitHub repository)
All Terraform, GitOps manifests, and scripts live in one repo. ArgoCD points to subdirectories within it. This keeps AI-assisted development simple (unified context) and is appropriate for a personal project.

### 2. Hybrid dev workflow (direct helm/kubectl + ArgoCD validation)
- **Inner loop (fast iteration)**: AI edits manifests → `helm template` to validate → `helm upgrade --install` or `kubectl apply` to deploy directly → verify with `kubectl`. Sub-30-second feedback cycles.
- **Outer loop (GitOps validation)**: Once a component works, commit to git → ArgoCD syncs → confirm Synced+Healthy. This validates the production path.

> Why not `argocd app sync --local`? It has [known bugs](https://github.com/argoproj/argo-cd/issues/22561) where subsequent syncs fail. Why not push-to-git-then-sync? Too slow (30-60s per iteration) for an "Analyze → Fix → Repeat" loop.

### 3. Helm for all components
cert-manager, Istio, ECK, and Keycloak all have official Helm charts. Environment differences handled via `values-local.yaml` / `values-aws.yaml` overlays. ArgoCD has first-class Helm support.

### 4. App of Apps pattern for ArgoCD
A single bootstrap Helm chart contains ArgoCD `Application` templates for each component. Sync waves control deployment order. Environment selection via values files.

### 5. Istio sidecar mode (not ambient mesh)
Sidecar mode is mature, well-documented, and provides clearer per-pod observability for understanding traffic patterns and defining Network Policies.

---

## Repository Structure

```
eck-2026-project/
├── docs/                            # Project documentation
│   ├── getting-started.md
│   ├── architecture.md
│   ├── teardown-and-rebuild.md
│   └── implementation-plan.md       # This file
│
├── scripts/
│   ├── setup-local.sh               # Tool install verification
│   ├── port-forward.sh              # Quick access to local services
│   └── teardown-local.sh            # Local stack teardown
│
├── terraform/                       # AWS infrastructure only
│   ├── terragrunt.hcl               # Root config (S3 backend)
│   ├── modules/
│   │   ├── vpc/                     # Wraps terraform-aws-modules/vpc/aws
│   │   ├── eks/                     # Wraps terraform-aws-modules/eks/aws
│   │   ├── argocd-bootstrap/        # Helm provider deploys ArgoCD
│   │   ├── eks-addons/              # LB Controller, External DNS, EBS CSI
│   │   ├── acm/                     # ACM certificate lookup
│   │   └── security-context/        # IAM roles, CIDR restrictions
│   └── environments/
│       └── dev/
│           ├── terragrunt.hcl
│           ├── vpc/
│           ├── eks/
│           ├── argocd-bootstrap/
│           ├── eks-addons/
│           ├── acm/
│           └── security-context/
│
├── gitops/                          # Everything ArgoCD manages
│   ├── bootstrap/                   # App of Apps parent chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml              # Common values
│   │   ├── values-local.yaml
│   │   ├── values-aws.yaml
│   │   └── templates/               # One ArgoCD Application per component
│   │       ├── cert-manager.yaml            (sync-wave: 1)
│   │       ├── cert-manager-resources.yaml  (sync-wave: 2)
│   │       ├── istio-base.yaml              (sync-wave: 2)
│   │       ├── istio-istiod.yaml            (sync-wave: 3)
│   │       ├── kiali.yaml                   (sync-wave: 3)
│   │       ├── prometheus.yaml              (sync-wave: 3)
│   │       ├── tls-certificates.yaml        (sync-wave: 3)
│   │       ├── eck-operator.yaml            (sync-wave: 4)
│   │       ├── elastic-stack.yaml           (sync-wave: 5)
│   │       ├── kube-state-metrics.yaml      (sync-wave: 5)
│   │       ├── keycloak.yaml                (sync-wave: 6)
│   │       ├── monitoring.yaml              (sync-wave: 6)
│   │       ├── network-policies.yaml        (sync-wave: 7)
│   │       ├── aws-ingress.yaml             (sync-wave: 5, AWS only)
│   │       └── repo-secret.yaml             (GitHub repo auth)
│   └── apps/                        # Per-component config
│       ├── cert-manager/            # Self-signed ClusterIssuer
│       ├── eck/
│       │   ├── operator/            # ECK operator values
│       │   ├── stack/               # Elasticsearch + Kibana CRs (base + overlays)
│       │   └── monitoring/          # Fleet Server + Elastic Agent
│       ├── keycloak/                # Keycloak CR + realm import (base + overlays)
│       ├── tls/                     # TLS certificates for all components
│       ├── network-policies/        # NetworkPolicy manifests
│       └── aws-ingress/             # ALB Ingress resources (AWS only)
│
└── .github/
    ├── agents/                      # Copilot agent definitions
    └── prompts/                     # Reusable Copilot prompts
```

---

## Implementation Phases

### Phase 0: Local Environment Setup ✅

- Add `~/.rd/bin` to PATH in shell RC file
- Install missing tools: `brew install argocd istioctl awscli`
- Initialize git repo, create `.gitignore`, push to GitHub (private repo)
- **Verify**: `kubectl get nodes`, `helm version`, `argocd version --client`

### Phase 1: Scaffold Repository ✅

- Create the directory structure above
- Create skeleton files: `gitops/bootstrap/Chart.yaml`, root `terragrunt.hcl`, `.gitignore`
- Push initial commit

### Phase 2: ArgoCD on Local Cluster ✅

- `helm install argocd argo/argo-cd -n argocd` with NodePort + insecure server
- Port-forward to access UI at `localhost:8080`
- Connect ArgoCD to the GitHub repo
- Deploy the (initially empty) App of Apps bootstrap chart
- **Verify**: ArgoCD UI accessible, bootstrap app shows Synced
- **Note**: GitHub repo connection deferred until `gh auth login`

### Phase 3: cert-manager (sync-wave 1) ✅

- Add ArgoCD Application template pointing to the jetstack Helm chart
- Create self-signed ClusterIssuer for local dev
- **Inner-loop**: `helm install cert-manager jetstack/cert-manager` first, validate, then commit for ArgoCD
- **Verify**: `kubectl get clusterissuer` shows Ready

### Phase 4: Istio (sync-waves 2-3) ✅

- Deploy `istio/base` (CRDs) then `istio/istiod` (control plane) as separate ArgoCD apps
- Enable sidecar injection per-namespace via labels
- **Verify**: `istioctl analyze` clean, test pod shows `istio-proxy` sidecar

### Phase 5: ECK Operator + Elastic Stack (sync-waves 4-5) ✅

- Deploy ECK operator from `helm.elastic.co` (version 3.3.0, updated from plan's 2.16.1)
- Deploy single-node Elasticsearch (2GB RAM, `allow_mmap: false` for K3s) + Kibana
- Label `elastic` namespace for Istio sidecar injection
- **Verify**: Elasticsearch health green, Kibana accessible via port-forward, 2/2 containers (Istio sidecar confirmed)

### Phase 6: Keycloak (sync-wave 6) ✅

- Deploy using the Keycloak Operator (avoids Bitnami licensing issues)
- Embedded H2 database for both local and AWS (avoids RDS cost and 30+ min create/destroy cycles)
- Configure realm, client, and test user
- Integrate as OIDC provider for ArgoCD and Kibana SSO
- **Verify**: Admin console accessible, SSO login to ArgoCD works
- **Note**: Keycloak Operator installed via raw manifests from `keycloak-k8s-resources` repo (no official Helm chart)

### Phase 7: Network Policies (sync-wave 7) ✅

- Use Istio telemetry to observe actual traffic patterns first
- Apply default-deny per namespace, then selective allow rules
- 15 NetworkPolicies across argocd, elastic, keycloak namespaces
- **Verify**: Authorized traffic works, unauthorized traffic is blocked

### Phase 8: AWS Terraform Infrastructure ✅

- Terraform modules wrapping public modules: VPC (single NAT gateway), EKS (Spot instances, 2 AZs), ArgoCD bootstrap via Helm provider
- Additional modules: EKS addons (LB Controller, External DNS, EBS CSI), ACM certificate lookup, security context (IAM roles, CIDR restrictions)
- Terragrunt for DRY config + S3 backend
- **Cost controls**: Single NAT (~$1/day), Spot instances (60-80% savings), `terraform destroy` after each session

### Phase 9: Lift and Shift to EKS ✅

- ArgoCD on EKS points to same repo, uses `values-aws.yaml` overlays
- Key differences: ALB ingress, gp3 EBS storage, ACM for public TLS, IRSA for IAM, multi-node Elasticsearch (3 nodes, 4GB each)
- AWS-specific components: aws-ingress (ALB + Route53 via External DNS), CIDR-restricted access
- **Verified**: All ArgoCD apps Synced+Healthy, Kibana accessible via domain, OIDC SSO works end-to-end

---

## Local vs AWS Differences

| Aspect | Local (Rancher Desktop) | AWS (EKS) |
|--------|------------------------|-----------|
| Ingress | Traefik (pre-installed), port-forward | AWS Load Balancer Controller, ALB/NLB |
| Storage | `local-path` StorageClass | `gp3` EBS CSI driver |
| TLS | Self-signed ClusterIssuer | ACM for public-facing certs (free, auto-renewing, native ALB integration) |
| IAM | None | IRSA for service accounts |
| Elasticsearch | 1 node, 2GB, `allow_mmap: false` | 2-3 nodes, 4GB each, default mmap |
| DNS | localhost via port-forward | Route53 records (External DNS) |
| Keycloak DB | Embedded H2 | Embedded H2 (acceptable for dev; avoids RDS cost/teardown delays) |

---

## Resource Budget (Local Cluster - 10GB RAM)

| Component | Memory |
|-----------|--------|
| K3s system (CoreDNS, Traefik, etc.) | ~500MB |
| ArgoCD | ~500MB |
| cert-manager | ~100MB |
| Istio (istiod + sidecars) | ~500MB |
| Prometheus (Istio metrics) | ~256–512MB |
| Kiali | ~64–256MB |
| kube-state-metrics | ~100MB |
| Elasticsearch (1 node) | 2GB |
| Kibana | 512MB–1GB |
| Fleet Server + Elastic Agent | ~500MB |
| Keycloak | ~500MB |
| **Total** | **~6–7.5GB** |

Leaves ~2.5–4GB headroom. If tight, Rancher Desktop VM memory can be increased in Preferences.

---

## Component Dependency Graph

```
cert-manager (sync-wave: 1)
├── cert-manager-resources (sync-wave: 2) — CA + ClusterIssuers
├── Istio base (sync-wave: 2) + istiod (sync-wave: 3) — webhook certs
│       ├── Prometheus + Kiali (sync-wave: 3) — Istio telemetry
│       ├── TLS certificates (sync-wave: 3) — component certs
│       └── ECK Operator (sync-wave: 4) — sidecar injection
│               └── Elastic Stack + kube-state-metrics (sync-wave: 5)
│                       ├── Keycloak (sync-wave: 6) — OIDC provider for SSO
│                       ├── Monitoring (sync-wave: 6) — Fleet Server + Elastic Agent
│                       └── Network Policies (sync-wave: 7) — after traffic patterns known
```

---

## Verification Strategy

Each phase has inline verification steps. End-to-end checklist:
1. ArgoCD UI shows all apps Synced + Healthy
2. `kubectl get certificates -A` — all Ready
3. `istioctl analyze` — no issues
4. `kubectl get elasticsearch -n elastic` — green
5. Kibana accessible, login works
6. Keycloak admin console accessible, SSO to ArgoCD works
7. Network Policies: `kubectl exec` from unauthorized pod → connection refused
8. (AWS) `terraform plan` shows no drift after ArgoCD sync

---

## Risk Mitigations

| Risk | Mitigation |
|------|------------|
| Rancher Desktop VM OOM | Monitor `kubectl top nodes`. Increase VM to 12GB if needed. Reduce ES to 1.5GB. |
| Forgotten AWS resources | Budget alert at $50. Check for orphaned ELBs/EBS after `terraform destroy`. |
| Spot instance interruptions | Acceptable for dev. 2-node minimum so one survives. |
| Bitnami Helm chart licensing | Use Keycloak Operator + upstream `quay.io/keycloak/keycloak` images. |
