# ACM module — looks up the existing wildcard certificate and hosted zone
# The wildcard cert (*.hermanwong.io) is managed outside this repo.

variable "hosted_zone_id" {
  description = "Route53 Public Hosted Zone ID"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the existing ACM wildcard certificate"
  type        = string
}

# Look up the hosted zone to get the domain name
data "aws_route53_zone" "main" {
  zone_id = var.hosted_zone_id
}

locals {
  domain_name = trimsuffix(data.aws_route53_zone.main.name, ".")
}

# Outputs
output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = var.certificate_arn
}

output "domain_name" {
  description = "Base domain name from the hosted zone"
  value       = local.domain_name
}

output "keycloak_fqdn" {
  description = "FQDN for Keycloak"
  value       = "keycloak.${local.domain_name}"
}

output "kiali_fqdn" {
  description = "FQDN for Kiali"
  value       = "kiali.${local.domain_name}"
}

output "kibana_fqdn" {
  description = "FQDN for Kibana"
  value       = "kibana.${local.domain_name}"
}

output "argocd_fqdn" {
  description = "FQDN for ArgoCD"
  value       = "argocd.${local.domain_name}"
}

output "hosted_zone_id" {
  description = "Route53 Hosted Zone ID (passthrough)"
  value       = var.hosted_zone_id
}
