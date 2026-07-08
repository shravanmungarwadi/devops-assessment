terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Separate remote state per environment, using a distinct key so dev and
  # prod state files never collide. In plan-only / local review, comment this
  # block out or run `terraform init -backend=false`.
  # backend "s3" {
  #   bucket         = "REPLACE_ME-terraform-state-bucket"
  #   key            = "devops-assessment/dev/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "REPLACE_ME-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
