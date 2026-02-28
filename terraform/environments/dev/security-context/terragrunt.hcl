include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../../modules/security-context"
}

# No inputs needed - this module just detects the current IP
inputs = {}
