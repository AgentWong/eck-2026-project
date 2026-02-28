include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../../modules/eks-addons"
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "eck-2026-dev"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-mock-1", "subnet-mock-2"]
    public_subnets  = ["subnet-mock-3", "subnet-mock-4"]
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

dependency "acm" {
  config_path = "../acm"

  mock_outputs = {
    certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/mock"
    domain_name     = "example.com"
    hosted_zone_id  = "ZXXXXXXXXXXXMOCK"
    keycloak_fqdn   = "keycloak.example.com"
    kiali_fqdn      = "kiali.example.com"
    kibana_fqdn     = "kibana.example.com"
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

dependency "security_context" {
  config_path = "../security-context"

  mock_outputs = {
    allowed_cidr = "0.0.0.0/32"
    allowed_ip   = "0.0.0.0"
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

inputs = {
  cluster_name                       = dependency.eks.outputs.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  oidc_provider_arn                  = dependency.eks.outputs.oidc_provider_arn
  vpc_id                             = dependency.vpc.outputs.vpc_id
  hosted_zone_id                     = dependency.acm.outputs.hosted_zone_id
  domain_name                        = dependency.acm.outputs.domain_name
  allowed_cidr                       = dependency.security_context.outputs.allowed_cidr
}
