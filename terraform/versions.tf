terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  # Usa la configuración AWS CLI (aws configure)
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}