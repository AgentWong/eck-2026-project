# Teardown and Rebuild

Use this guide to destroy and recreate the entire stack. This validates that all configuration is captured in code and nothing depends on manual state.

## Local Stack: Teardown

Teardown **must** go in reverse dependency order to avoid stuck finalizers.

### Step 1: Uninstall Bootstrap Chart (removes all ArgoCD Applications)

```bash
# This removes all ArgoCD Application resources, which triggers cascading deletes
# of the resources they manage (due to resources-finalizer.argocd.argoproj.io)
helm uninstall eck-bootstrap -n argocd 2>/dev/null

# Wait for ArgoCD to finish cleaning up managed resources
kubectl wait --for=delete application --all -n argocd --timeout=300s
```

### Step 2: Clean Up Agent Host State

```bash
# Clean up agent state from host filesystem (hostPath volumes)
# Without this, stale fleet.enc enrollment tokens cause 401 errors on rebuild
kubectl run cleanup-agent-state --rm -i --restart=Never --image=busybox -n elastic \
  --overrides='{"spec":{"containers":[{"name":"c","image":"busybox","command":["sh","-c","rm -rf /var/lib/elastic-agent/elastic/*/state/* && echo cleaned"],"volumeMounts":[{"name":"state","mountPath":"/var/lib/elastic-agent"}]}],"volumes":[{"name":"state","hostPath":{"path":"/var/lib/elastic-agent","type":"DirectoryOrCreate"}}]}}' 2>/dev/null
```

### Step 3: Keycloak Operator (not managed by ArgoCD)

```bash
# Delete Keycloak Operator and CRDs (installed via raw manifests, not ArgoCD)
kubectl -n keycloak delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/kubernetes.yml 2>/dev/null
kubectl delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml 2>/dev/null
kubectl delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml 2>/dev/null
```

### Step 4: Delete Namespaces

```bash
# Delete application namespaces (removes any lingering resources + PVCs)
kubectl delete namespace elastic keycloak elastic-system istio-system cert-manager 2>/dev/null

# Wait for namespace termination
kubectl wait --for=delete namespace/elastic --timeout=120s 2>/dev/null
```

### Step 5: ArgoCD

```bash
helm uninstall argocd -n argocd
kubectl delete namespace argocd
```

### Step 6: Verify Clean State

```bash
# Only system namespaces should remain
kubectl get namespaces

# No lingering CRDs
kubectl get crds | grep -E 'cert-manager|istio|elastic|keycloak|argoproj'

# No helm releases
helm list -A

# No leftover PVCs
kubectl get pvc -A
```

Expected output: only `default`, `kube-system`, `kube-public`, `kube-node-lease` namespaces. No matching CRDs. No helm releases (except `traefik`/`traefik-crd` which are K3s system components).

### Nuclear Option (Fastest)

If you want the fastest clean slate, reset the entire K3s cluster:

**Rancher Desktop** → Preferences → Kubernetes → **Reset Kubernetes**

This destroys everything including system components and recreates the cluster from scratch.

---

## Local Stack: Full Rebuild (GitOps)

ArgoCD manages the full stack via the App of Apps bootstrap chart. Only ArgoCD itself and the Keycloak Operator (no official Helm chart) are installed manually — everything else is synced automatically via sync waves.

### Prerequisites

```bash
./scripts/setup-local.sh

# Create .env from template (if not already done) and set your PAT
cp -n .env.example .env
# Edit .env to set GITHUB_PAT, or leave commented to use `gh auth token`

# Load environment
source .env 2>/dev/null
GITHUB_PAT="${GITHUB_PAT:-$(gh auth token)}"
```

### Step 1: Helm Repos

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### Step 2: ArgoCD

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set 'configs.params.server\.insecure=true' \
  --set server.service.type=NodePort \
  --version 9.4.1

kubectl wait --for=condition=Ready pods --all -n argocd --timeout=120s
```

### Step 3: Keycloak Operator (not available as Helm chart)

```bash
# Install CRDs
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml

# Install Operator
kubectl create namespace keycloak
kubectl -n keycloak apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/kubernetes.yml
kubectl wait --for=condition=Ready pods --all -n keycloak --timeout=90s
```

### Step 4: Prepare Namespaces

```bash
# Create elastic namespace with Istio sidecar injection
kubectl create namespace elastic
kubectl label namespace elastic istio-injection=enabled
```

### Step 5: Deploy App of Apps Bootstrap Chart

This single command triggers ArgoCD to sync all components in order via sync waves:

| Wave | Components |
|------|-----------|
| 1 | cert-manager |
| 2 | istio-base, cert-manager-resources (CA + ClusterIssuers) |
| 3 | istiod, prometheus, kiali, tls-certificates |
| 4 | eck-operator |
| 5 | elastic-stack, kube-state-metrics |
| 6 | keycloak, monitoring (Fleet Server + Elastic Agent) |
| 7 | network-policies |

```bash
helm install eck-bootstrap gitops/bootstrap/ \
  -n argocd \
  -f gitops/bootstrap/values-local.yaml \
  --set repo.password="${GITHUB_PAT}"
```

### Step 5.5: Enable ArgoCD TLS

After the App of Apps syncs, cert-manager issues a TLS certificate for ArgoCD (the `argocd-server-tls` secret in the `argocd` namespace). Upgrade ArgoCD to enable TLS:

```bash
# Wait for the TLS certificate to be ready
kubectl wait --for=condition=Ready certificate/argocd-server-tls -n argocd --timeout=120s

# Upgrade ArgoCD to enable TLS (removes insecure mode)
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --reuse-values \
  --set 'configs.params.server\.insecure=false' \
  --version 9.4.1

kubectl wait --for=condition=Ready pods --all -n argocd --timeout=120s
```

### Step 6: Watch ArgoCD Sync

```bash
# Watch Applications sync (Ctrl+C when all show Synced/Healthy)
kubectl get applications -n argocd -w

# Or check the ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

> **Note:** Full sync takes 5-10 minutes due to sync waves. Elasticsearch and Kibana (wave 5) take the longest to become healthy.

### Step 7: Restart Pods for Istio Sidecar Injection

Pods created by the ECK operator in the `elastic` namespace need a restart to pick up Istio sidecars (the namespace was labeled before pods were created, but the sidecar injector may not inject on the first creation depending on timing with istiod).

```bash
# Restart Elasticsearch, Kibana, and Fleet Server pods
kubectl delete pod -n elastic -l elasticsearch.k8s.elastic.co/cluster-name=elasticsearch
kubectl delete pod -n elastic -l kibana.k8s.elastic.co/name=kibana
kubectl delete pod -n elastic -l agent.k8s.elastic.co/name=fleet-server

# Wait for everything to recover
kubectl wait --for=jsonpath='{.status.health}'=green elasticsearch/elasticsearch -n elastic --timeout=300s
kubectl wait --for=jsonpath='{.status.health}'=green kibana/kibana -n elastic --timeout=300s
kubectl wait --for=jsonpath='{.status.health}'=green agent/fleet-server -n elastic --timeout=300s

# Verify istio-proxy is running as a native sidecar (init container with restartPolicy=Always)
kubectl get pods -n elastic -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.initContainers[*]}{.name}{" "}{end}{"\n"}{end}'
```

> **Note:** The Elastic Agent DaemonSet is excluded from sidecar injection via `sidecar.istio.io/inject: "false"` because it uses `hostNetwork: true`.

### Step 8: Verify Everything

```bash
echo "=== ArgoCD Applications ==="
kubectl get applications -n argocd

echo "=== Pods ==="
kubectl get pods -A | grep -v kube-system

echo "=== Elasticsearch ==="
kubectl get elasticsearch -n elastic

echo "=== Kibana ==="
kubectl get kibana -n elastic

echo "=== Elastic Agents ==="
kubectl get agent -n elastic

echo "=== Keycloak ==="
kubectl get keycloak -n keycloak

echo "=== ClusterIssuers ==="
kubectl get clusterissuer

echo "=== TLS Certificates ==="
kubectl get certificate -A

echo "=== Prometheus ==="
kubectl get pods -l app.kubernetes.io/name=prometheus -n istio-system

echo "=== Helm Releases ==="
helm list -A

echo "=== Network Policies ==="
kubectl get networkpolicies -A

echo "=== Resource Usage ==="
kubectl top nodes
```

### Step 9: Test GitOps Self-Heal

```bash
# Delete a network policy — ArgoCD should recreate it within ~3 minutes
kubectl delete networkpolicy default-deny-ingress -n argocd
kubectl get applications network-policies -n argocd -w
```

### Step 10: Verify TLS and SSO

```bash
# Start port-forwards (all services now use HTTPS)
./scripts/port-forward.sh all

# Verify Keycloak HTTPS
curl -sk https://localhost:8443/realms/eck-2026/.well-known/openid-configuration | jq .issuer
# Expected: "https://localhost:8443/realms/eck-2026"

# Verify ArgoCD HTTPS
curl -sk https://localhost:8080 | head -5

# Verify Elasticsearch role mappings
ES_PASS=$(kubectl get secret elasticsearch-es-elastic-user -n elastic -o jsonpath='{.data.elastic}' | base64 -d)
curl -sk -u "elastic:${ES_PASS}" https://localhost:9200/_security/role_mapping | jq .

# Verify Kibana OIDC login
# Open https://localhost:5601 in browser
# Should see "Log in with Keycloak" button alongside "Log in with username/password"
# Click "Log in with Keycloak" → redirects to Keycloak → login as admin/admin → back to Kibana
```

Now access the services — see [Getting Started](getting-started.md) for URLs and credentials.

**Port-forward reference (all HTTPS):**
- ArgoCD: `kubectl port-forward svc/argocd-server -n argocd 8080:443` → https://localhost:8080 (local) / https://argocd.hermanwong.io (AWS)
- Kibana: `kubectl port-forward svc/kibana-kb-http -n elastic 5601:5601` → https://localhost:5601 (local) / https://kibana.hermanwong.io (AWS)
- Keycloak: `kubectl port-forward svc/keycloak-service -n keycloak 8443:8443` → https://localhost:8443 (local) / https://keycloak.hermanwong.io (AWS)
- Elasticsearch: `kubectl port-forward svc/elasticsearch-es-http -n elastic 9200:9200` → https://localhost:9200
- Kiali: `kubectl port-forward svc/kiali -n istio-system 20001:20001` → https://localhost:20001 (local) / https://kiali.hermanwong.io (AWS)

---

## AWS Stack: Teardown

> Requires: `aws configure` completed, valid AWS credentials

**Always destroy in reverse order to avoid orphaned resources.**

```bash
# 1. Remove ArgoCD-managed K8s resources
helm uninstall eck-bootstrap -n argocd 2>/dev/null

# 2. Delete ALBs created by the AWS Load Balancer Controller
#    These are NOT Terraform-managed — if left, they hold ENIs that block VPC destroy.
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName]' --output table
# Delete each ALB shown above:
# aws elbv2 delete-load-balancer --load-balancer-arn <ARN>
# Wait for ALB to drain
sleep 30
# Clean up orphaned target groups (no longer attached to any ALB)
aws elbv2 describe-target-groups --query 'TargetGroups[?!LoadBalancerArns[0]].[TargetGroupArn]' --output text \
  | xargs -I{} aws elbv2 delete-target-group --target-group-arn {}

# 3. ArgoCD Bootstrap
cd terraform/environments/dev/argocd-bootstrap
terragrunt destroy -auto-approve

# 4. EKS
cd terraform/environments/dev/eks
terragrunt destroy -auto-approve

# 5. VPC
cd terraform/environments/dev/vpc
terragrunt destroy -auto-approve

# NOTE: Never pipe or redirect stdout/stderr for terragrunt destroy commands
# (no | tee, | tail, > file, etc.). Terragrunt requires a direct TTY — piping
# or redirecting causes it to hang indefinitely with no progress.
```

### Post-Teardown: Manual Cleanup Check

Some resources are created outside of Terraform by Kubernetes controllers and **will not be removed by `terragrunt run-all destroy`**. Run these checks after every teardown to avoid surprise billing.

```bash
# --- Resources commonly left behind ---

# 1. ALBs/NLBs created by AWS Load Balancer Controller (most common orphan)
aws elbv2 describe-load-balancers --region us-west-2 \
  --query 'LoadBalancers[*].[LoadBalancerName,State.Code,CreatedTime]' --output table

# 2. Target Groups (orphaned after ALB deletion)
aws elbv2 describe-target-groups --region us-west-2 \
  --query 'TargetGroups[?!LoadBalancerArns[0]].[TargetGroupName,TargetGroupArn]' --output table

# 3. Security Groups created by the LB controller or EKS (tagged k8s or eck-2026)
#    These block VPC deletion if still present.
aws ec2 describe-security-groups --region us-west-2 \
  --filters "Name=tag-key,Values=kubernetes.io/cluster/eck-2026-dev" \
  --query 'SecurityGroups[*].[GroupId,GroupName]' --output table

# 4. ENIs left by ALBs or Lambda (block subnet/SG deletion)
aws ec2 describe-network-interfaces --region us-west-2 \
  --filters "Name=status,Values=available" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Description]' --output table

# 5. EBS Volumes (PVCs that weren't reclaimed)
aws ec2 describe-volumes --region us-west-2 \
  --filters "Name=status,Values=available" "Name=tag:kubernetes.io/cluster/eck-2026-dev,Values=owned" \
  --query 'Volumes[*].[VolumeId,Size,CreateTime]' --output table

# 6. Elastic IPs (unassociated = $0.005/hr each)
aws ec2 describe-addresses --region us-west-2 \
  --query 'Addresses[?!AssociationId].[AllocationId,PublicIp]' --output table

# 7. NAT Gateways (~$1/day if still running)
aws ec2 describe-nat-gateways --region us-west-2 \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[*].[NatGatewayId,State,SubnetId]' --output table

# 8. Route53 records created by External DNS
#    External DNS uses a "sync" policy — records should be deleted when Ingress
#    resources are removed, but verify manually if the controller pod was killed
#    before it could clean up.
aws route53 list-resource-record-sets --hosted-zone-id <YOUR_ZONE_ID> \
  --query 'ResourceRecordSets[?Type!=`NS` && Type!=`SOA`].[Name,Type]' --output table

# 9. CloudWatch Log Groups (EKS control plane logs, ~$0.50/GB stored)
aws logs describe-log-groups --region us-west-2 \
  --log-group-name-prefix "/aws/eks/eck-2026" \
  --query 'logGroups[*].[logGroupName,storedBytes]' --output table
```

**Why these get left behind:**
| Resource | Created by | Why it survives destroy |
|----------|-----------|----------------------|
| ALBs / Target Groups | AWS LB Controller (K8s Ingress) | Controller creates them via AWS API, not Terraform |
| Security Groups | EKS / LB Controller | Tagged for K8s but managed outside Terraform state |
| EBS Volumes | EBS CSI Driver (PVCs) | `Retain` reclaim policy or delete ordering issues |
| Route53 Records | External DNS | Controller may not clean up if killed mid-reconcile |
| CloudWatch Logs | EKS control plane | Created by AWS, not in Terraform state |

**Do NOT destroy** the S3 state bucket (`YOUR_TERRAFORM_STATE_BUCKET`) — this is persistent infrastructure.

## AWS Stack: Rebuild

> Requires: `aws configure` completed, S3 backend bucket exist

```bash
# 0. Load PAT
source .env 2>/dev/null
GITHUB_PAT="${GITHUB_PAT:-$(gh auth token)}"

# 1. VPC
cd terraform/environments/dev/vpc
terragrunt apply

# 2. EKS
cd terraform/environments/dev/eks
terragrunt apply

# 3. ACM (looks up existing *.hermanwong.io wildcard cert — no cert created)
cd terraform/environments/dev/acm
terragrunt apply

# 4. EKS Addons (LB Controller, External DNS, EBS CSI)
cd terraform/environments/dev/eks-addons
terragrunt apply

# 5. ArgoCD Bootstrap
cd terraform/environments/dev/argocd-bootstrap
terragrunt apply

# 6. Update kubeconfig
aws eks update-kubeconfig --name eck-2026-dev --region us-west-2

# 7. Verify cluster
kubectl get nodes

# 7.5. Install Keycloak Operator (no official Helm chart — must be installed manually)
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
kubectl create namespace keycloak
kubectl -n keycloak apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/kubernetes.yml
kubectl wait --for=condition=Ready pods --all -n keycloak --timeout=90s

# 8. Deploy App of Apps bootstrap chart (allowedCidr + natGatewayIp + acmCertificateArn set dynamically from Terraform outputs)
ALLOWED_CIDR=$(cd terraform/environments/dev/security-context && terragrunt output -raw allowed_cidr)
NAT_GW_IP=$(cd terraform/environments/dev/vpc && terragrunt output -raw nat_gateway_public_ip)
ACM_CERT_ARN=$(cd terraform/environments/dev/acm && terragrunt output -raw certificate_arn)
helm install eck-bootstrap gitops/bootstrap/ \
  -n argocd \
  -f gitops/bootstrap/values-aws.yaml \
  --set repo.password="${GITHUB_PAT}" \
  --set awsIngress.allowedCidr="${ALLOWED_CIDR}" \
  --set awsIngress.natGatewayIp="${NAT_GW_IP}" \
  --set awsIngress.acmCertificateArn="${ACM_CERT_ARN}"

# 9. Verify all apps sync (aws-ingress app creates ALBs + Route53 records via External DNS)
kubectl get applications -n argocd

# 10. Verify ArgoCD SSO works
# Open https://argocd.hermanwong.io — click "Log in via Keycloak" and login as admin/admin
```

**AWS service endpoints after rebuild:**

| Service | URL |
|---------|-----|
| ArgoCD | https://argocd.hermanwong.io |
| Kibana | https://kibana.hermanwong.io |
| Keycloak | https://keycloak.hermanwong.io |
| Kiali | https://kiali.hermanwong.io |

**Keycloak SSO credentials (eck-2026 realm):**

| User | Password | ArgoCD Role | Kibana Role |
|------|----------|-------------|-------------|
| `admin` | `admin` | role:admin (full access) | superuser |
| `viewer` | `viewer` | role:readonly | kibana_admin + viewer |

**Cost warning:** AWS resources cost approximately $2.30/8-hr day while running (EKS control plane, 2× m5.xlarge Spot, NAT Gateway). Always run teardown when done testing.
