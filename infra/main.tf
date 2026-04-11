# ============================================================
# Terraform configuration — provider + remote state backend
# ============================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — stored in S3, locked via DynamoDB
  # This bucket was created manually (bootstrap) before Terraform init
  backend "s3" {
    bucket         = "project-flux-tfstate-507221376720"
    key            = "project-flux/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "project-flux-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "project-flux"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
