terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67.0"
    }
    minio = {
      source  = "aminueza/minio"
      version = "3.8.0"
    }
  }
}
