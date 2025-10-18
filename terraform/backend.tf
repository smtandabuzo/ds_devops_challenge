terraform {
  backend "s3" {
    bucket         = "ds-devops-tfstate-810772959397"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}
