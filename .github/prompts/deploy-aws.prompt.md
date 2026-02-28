---
description: 'Deploy AWS infrastructure and ECK stack via Terraform and ArgoCD'
agent: 'AWS EKS Tester'
tools:
  ['execute', 'read', 'agent', 'edit', 'search', 'todo']
---

Deploy the complete AWS infrastructure and ECK 2026 stack.

## Pre-flight Checks

1. Verify AWS credentials: `aws sts get-caller-identity`
2. Verify S3 state bucket exists: `aws s3 ls s3://YOUR_TERRAFORM_STATE_BUCKET`
3. Verify tools installed: `terraform`, `terragrunt`, `kubectl`, `helm`, `aws`

If any pre-flight check fails, **stop and report what is missing**.

## Infrastructure Deployment

Read `docs/teardown-and-rebuild.md` section "AWS Stack: Rebuild" for exact commands.

1. **VPC**: `cd terraform/environments/dev/vpc && terragrunt plan && terragrunt apply`
2. **EKS**: `cd terraform/environments/dev/eks && terragrunt plan && terragrunt apply`
3. **ACM** (looks up existing wildcard cert): `cd terraform/environments/dev/acm && terragrunt plan && terragrunt apply`
4. **EKS Addons** (LB Controller, External DNS, EBS CSI): `cd terraform/environments/dev/eks-addons && terragrunt plan && terragrunt apply`
5. **ArgoCD Bootstrap**: `cd terraform/environments/dev/argocd-bootstrap && terragrunt plan && terragrunt apply`
6. **kubeconfig**: `aws eks update-kubeconfig --name eck-2026-dev --region us-west-2`
7. **Verify cluster**: `kubectl get nodes`

## Application Deployment

8. **Install Keycloak Operator** (no Helm chart — must be done manually before helm install):
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
   kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
   kubectl create namespace keycloak
   kubectl -n keycloak apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.5.3/kubernetes/kubernetes.yml
   kubectl wait --for=condition=Ready pods --all -n keycloak --timeout=90s
   ```
9. Get allowed CIDR: `ALLOWED_CIDR=$(cd terraform/environments/dev/security-context && terragrunt output -raw allowed_cidr)`
10. Get NAT gateway IP: `NAT_GW_IP=$(cd terraform/environments/dev/vpc && terragrunt output -raw nat_gateway_public_ip)`
11. Get ACM certificate ARN: `ACM_CERT_ARN=$(cd terraform/environments/dev/acm && terragrunt output -raw certificate_arn)`
12. Get GitHub token (try `gh auth token` first; if `gh` is not installed, use `git credential fill` to retrieve the stored token)
13. Deploy bootstrap chart: `helm install eck-bootstrap gitops/bootstrap/ -n argocd -f gitops/bootstrap/values-aws.yaml --set repo.password="$(gh auth token 2>/dev/null || git credential fill <<< $'protocol=https\nhost=github.com' | grep ^password | cut -d= -f2)" --set awsIngress.allowedCidr="${ALLOWED_CIDR}" --set awsIngress.natGatewayIp="${NAT_GW_IP}" --set awsIngress.acmCertificateArn="${ACM_CERT_ARN}"`
13. Wait for all ArgoCD applications to sync and report status

## Rules

- Always run `terragrunt plan` before `apply` to review changes
- If any step fails, stop and report the error
- End the report with a **cost reminder**: resources cost ~$2.30/8-hr day while running
