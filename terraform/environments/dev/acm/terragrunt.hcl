include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  secrets = read_terragrunt_config("${get_parent_terragrunt_dir("root")}/environments/dev/secrets.hcl")
}

terraform {
  source = "../../../modules/acm"
}

inputs = {
  hosted_zone_id  = local.secrets.locals.hosted_zone_id
  certificate_arn = local.secrets.locals.acm_certificate_arn
}
