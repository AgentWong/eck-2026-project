#!/usr/bin/env bash
set -euo pipefail

# setup-local.sh — Verify local development prerequisites for eck-2026-project

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; MISSING+=("$1"); }

MISSING=()

echo "Checking prerequisites..."
echo ""

# Core tools
command -v terraform  >/dev/null 2>&1 && pass "terraform $(terraform version -json | head -1 | grep -o '"[0-9][^"]*"' | tr -d '"')" || fail "terraform not found"
command -v terragrunt >/dev/null 2>&1 && pass "terragrunt $(terragrunt --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" || fail "terragrunt not found"
command -v git        >/dev/null 2>&1 && pass "git $(git --version | awk '{print $3}')" || fail "git not found"
command -v gh         >/dev/null 2>&1 && pass "gh $(gh --version | head -1 | awk '{print $3}')" || fail "gh not found (brew install gh)"
command -v trivy      >/dev/null 2>&1 && pass "trivy $(trivy --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" || fail "trivy not found"

# Kubernetes tools (prefer ~/.rd/bin if available)
command -v kubectl    >/dev/null 2>&1 && pass "kubectl $(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4)" || fail "kubectl not found"
command -v helm       >/dev/null 2>&1 && pass "helm $(helm version --short 2>&1)" || fail "helm not found"

# Additional CLIs
command -v argocd     >/dev/null 2>&1 && pass "argocd $(argocd version --client --short 2>&1)" || fail "argocd not found (brew install argocd)"
command -v istioctl   >/dev/null 2>&1 && pass "istioctl $(istioctl version --remote=false 2>&1)" || fail "istioctl not found (brew install istioctl)"
command -v aws        >/dev/null 2>&1 && pass "aws $(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2)" || fail "aws cli not found (brew install awscli)"

echo ""

# Cluster connectivity
echo "Checking cluster connectivity..."
if kubectl get nodes >/dev/null 2>&1; then
  NODE_INFO=$(kubectl get nodes -o wide --no-headers 2>&1 | head -1)
  pass "Cluster reachable: $(echo "$NODE_INFO" | awk '{print $1, $3, $5}')"
else
  fail "Cannot reach Kubernetes cluster"
fi

echo ""

if [ ${#MISSING[@]} -eq 0 ]; then
  echo -e "${GREEN}All prerequisites satisfied.${NC}"
else
  echo -e "${RED}Missing prerequisites:${NC}"
  printf '  - %s\n' "${MISSING[@]}"
  exit 1
fi
