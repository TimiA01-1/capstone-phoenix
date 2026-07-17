terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "phoenix-capstone-tfstate-timilehin"
    key            = "phoenix/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "phoenix-capstone-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region  = "eu-west-2"
  profile = "phoenix"
}
