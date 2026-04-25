---
description: 'Destroy all AWS infrastructure to stop billing'
---

Tear down all AWS infrastructure for the ECK 2026 project to stop billing.

## Pre-Teardown

1. Verify AWS credentials: `aws sts get-caller-identity`
2. Preview what will be destroyed: run `terragrunt plan -destroy` in each module

## Teardown (REVERSE order)

Read `docs/teardown-and-rebuild.md` section "AWS Stack: Teardown" for exact commands.

1. Remove Kubernetes resources: `helm uninstall eck-bootstrap -n argocd`
2. **Delete ALBs created by the AWS Load Balancer Controller** (these are NOT Terraform-managed and will block VPC destroy if left):
   ```bash
   # List ALBs tagged with the cluster name
   aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName]' --output table
   # Delete each ALB (and its target groups will be cleaned up automatically)
   # aws elbv2 delete-load-balancer --load-balancer-arn <ARN>
   # Wait for ALBs to finish draining (~30s)
   sleep 30
   # Clean up orphaned target groups
   aws elbv2 describe-target-groups --query 'TargetGroups[?!LoadBalancerArns[0]].[TargetGroupArn]' --output text | xargs -I{} aws elbv2 delete-target-group --target-group-arn {}
   ```
3. ArgoCD Bootstrap: `cd terraform/environments/dev/argocd-bootstrap && terragrunt destroy -auto-approve`
4. EKS: `cd terraform/environments/dev/eks && terragrunt destroy -auto-approve`
5. VPC: `cd terraform/environments/dev/vpc && terragrunt destroy -auto-approve`

> **IMPORTANT**: Never pipe or redirect stdout/stderr when running `terragrunt destroy` (no `| tee`, `| tail`, `> file`, etc.). Terragrunt requires a direct TTY — piping or redirecting causes it to hang indefinitely.

## Post-Teardown Verification

Check for orphaned resources that could continue billing:

- EC2 Load Balancers (us-west-2)
- EBS Volumes tagged `eck-2026`
- NAT Gateways (~$1/day if left running)
- Elastic IPs
- Network Interfaces

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `eck`)]'
aws ec2 describe-nat-gateways --filter "Name=state,Values=available"
aws ec2 describe-volumes --filters "Name=status,Values=available"
```

**Do NOT destroy** the S3 state bucket (`YOUR_TERRAFORM_STATE_BUCKET`)

Report any resources that could not be destroyed.
