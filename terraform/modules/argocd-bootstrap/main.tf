# ArgoCD bootstrap module — deploys ArgoCD onto EKS via Helm provider

variable "cluster_endpoint" {
  type = string
}

variable "cluster_certificate_authority_data" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for public TLS"
  type        = string
  default     = ""
}

variable "allowed_cidr" {
  description = "CIDR allowed to access public-facing services"
  type        = string
  default     = "0.0.0.0/0"
}

variable "domain_name" {
  description = "Base domain name for public services"
  type        = string
  default     = ""
}

variable "keycloak_fqdn" {
  description = "FQDN for Keycloak"
  type        = string
  default     = ""
}

variable "kiali_fqdn" {
  description = "FQDN for Kiali"
  type        = string
  default     = ""
}

variable "kibana_fqdn" {
  description = "FQDN for Kibana"
  type        = string
  default     = ""
}

variable "argocd_fqdn" {
  description = "FQDN for ArgoCD"
  type        = string
  default     = ""
}

variable "nat_gateway_ip" {
  description = "Public EIP of the NAT Gateway, added to Keycloak ALB inbound-cidrs so in-cluster pods can reach Keycloak for OIDC"
  type        = string
  default     = ""
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.4.1"
  namespace        = "argocd"
  create_namespace = true

  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer"
          annotations = var.acm_certificate_arn != "" ? {
            "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
            "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
          } : {}
        }
      }
      configs = {
        cm = {
          "url" = "https://${var.argocd_fqdn}"
          # Native OIDC — no Dex. ArgoCD server talks directly to Keycloak.
          # The Keycloak ALB inbound-cidrs includes the VPC CIDR (10.0.0.0/16)
          # so pods can reach keycloak.hermanwong.io without leaving the VPC.
          "oidc.config" = <<-EOT
            name: Keycloak
            issuer: https://${var.keycloak_fqdn}/realms/eck-2026
            clientID: argocd
            clientSecret: REPLACE_WITH_STRONG_SECRET
            requestedScopes:
              - openid
              - profile
              - email
              - roles
            EOT
        }
        rbac = {
          "policy.csv"     = "g, admin, role:admin\ng, user, role:readonly\n"
          "policy.default" = "role:readonly"
        }
      }
    })
  ]
}

# Create a ConfigMap with AWS-specific values for ArgoCD apps to reference
resource "kubernetes_config_map" "aws_config" {
  metadata {
    name      = "aws-config"
    namespace = "argocd"
  }

  data = {
    acm_certificate_arn = var.acm_certificate_arn
    allowed_cidr        = var.allowed_cidr
    domain_name         = var.domain_name
    keycloak_fqdn       = var.keycloak_fqdn
    kiali_fqdn          = var.kiali_fqdn
    kibana_fqdn         = var.kibana_fqdn
    nat_gateway_ip      = var.nat_gateway_ip
  }

  depends_on = [helm_release.argocd]
}

# gp3 StorageClass using the EBS CSI driver — set as cluster default.
# Required for Elasticsearch and any other stateful workloads.
# The legacy gp2 in-tree driver is NOT used; this ensures the EBS CSI driver
# (installed via the eks-addons module) handles all dynamic provisioning.
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }
}

# Remove the default annotation from the legacy gp2 StorageClass to avoid
# having two default StorageClasses, which causes ambiguous PVC provisioning.
resource "kubernetes_annotations" "gp2_not_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
  force = true
}

output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "aws_config" {
  description = "AWS configuration values for downstream services"
  value = {
    acm_certificate_arn = var.acm_certificate_arn
    allowed_cidr        = var.allowed_cidr
    domain_name         = var.domain_name
    keycloak_fqdn       = var.keycloak_fqdn
    kiali_fqdn          = var.kiali_fqdn
    kibana_fqdn         = var.kibana_fqdn
    nat_gateway_ip      = var.nat_gateway_ip
  }
}
