terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.43.0"
    }
  }
}

provider "aws" {
  alias  = "primary"
  region = var.primary_aws_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_aws_region
}

