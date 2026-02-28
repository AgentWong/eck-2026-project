# Root terragrunt.hcl — common configuration for all modules

locals {
  secrets = read_terragrunt_config("${get_terragrunt_dir()}/environments/dev/secrets.hcl")
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = local.secrets.locals.terraform_state_bucket
    key          = "eck-2026/${path_relative_to_include()}/terraform.tfstate"
    region       = "us-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      Project     = "eck-2026"
      ManagedBy   = "terraform"
      Environment = "dev"
    }
  }
}
EOF
}
