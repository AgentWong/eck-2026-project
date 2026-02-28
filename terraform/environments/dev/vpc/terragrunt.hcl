include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../../modules/vpc"
}

inputs = {
  cluster_name = "eck-2026-dev"
  vpc_cidr     = "10.0.0.0/16"
  azs          = ["us-west-2a", "us-west-2b"]
}
