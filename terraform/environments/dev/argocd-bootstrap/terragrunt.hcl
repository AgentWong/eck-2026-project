include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../../modules/argocd-bootstrap"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    nat_gateway_public_ip = "1.2.3.4"
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
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

dependency "eks_addons" {
  config_path = "../eks-addons"

  mock_outputs = {
    lb_controller_role_arn = "arn:aws:iam::123456789012:role/mock-lb-controller"
    external_dns_role_arn  = "arn:aws:iam::123456789012:role/mock-external-dns"
    ebs_csi_role_arn       = "arn:aws:iam::123456789012:role/mock-ebs-csi"
    allowed_cidr           = "0.0.0.0/32"
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

dependency "acm" {
  config_path = "../acm"

  mock_outputs = {
    certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/mock"
    domain_name     = "example.com"
    hosted_zone_id  = "ZXXXXXXXXXXXMOCK"
    argocd_fqdn     = "argocd.example.com"
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
  cluster_endpoint                   = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  cluster_name                       = dependency.eks.outputs.cluster_name
  acm_certificate_arn                = dependency.acm.outputs.certificate_arn
  allowed_cidr                       = dependency.security_context.outputs.allowed_cidr
  domain_name                        = dependency.acm.outputs.domain_name
  argocd_fqdn                        = dependency.acm.outputs.argocd_fqdn
  keycloak_fqdn                      = dependency.acm.outputs.keycloak_fqdn
  kiali_fqdn                         = dependency.acm.outputs.kiali_fqdn
  kibana_fqdn                        = dependency.acm.outputs.kibana_fqdn
  nat_gateway_ip                     = dependency.vpc.outputs.nat_gateway_public_ip
}
