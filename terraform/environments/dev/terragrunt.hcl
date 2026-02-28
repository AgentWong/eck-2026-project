# Dev environment — common inputs for this environment
# Child modules include the root terragrunt.hcl directly

locals {
  environment  = "dev"
  region       = "us-west-2"
  cluster_name = "eck-2026-dev"
}
