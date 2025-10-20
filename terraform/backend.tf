terraform {
  backend "s3" {
    bucket         = "ds-devops-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

# Configure the MinIO provider
provider "minio" {
  minio_server = "minio:9000"
  minio_ssl      = false
  minio_insecure = true
  minio_user     = "minioadmin"
  minio_password = "minioadmin"
}

# Create the bucket for Terraform state
resource "minio_s3_bucket" "terraform_state" {
  bucket = "terraform-state"
  acl    = "private"
}

# Enable versioning for the bucket
resource "minio_s3_bucket_versioning" "versioning" {
  bucket = minio_s3_bucket.terraform_state.bucket
  versioning_configuration {
    status = "Enabled"
  }
}