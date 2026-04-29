terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "vpc_example" {
  source = "../../"

  environment          = "dev"
  name                 = "example-vpc"
  vpc_cidr_block       = "10.0.0.0/16"
  public_subnet_count  = 2
  private_subnet_count = 2
  db_subnet_count      = 2
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc_example.vpc_id
}