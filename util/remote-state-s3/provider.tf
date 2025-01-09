terraform {
  required_version = ">= 1.8.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.75.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      TfWorkingDir = path.cwd
    }
  }
}
