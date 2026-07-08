terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Separate state file/key from dev so the two environments can never
  # accidentally clobber each other's state.
  # backend "s3" {
  #   bucket         = "REPLACE_ME-terraform-state-bucket"
  #   key            = "devops-assessment/prod/terraform.tfstate"
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
