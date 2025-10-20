terraform {
  backend "s3" {
    bucket   = "terraform-state"
    key      = "terraform.tfstate"
    region   = "us-east-1"
    
    # MinIO endpoint - uses minio service name in GitHub Actions
    endpoint = "http://minio:9000"
    
    # MinIO access credentials
    access_key = "minioadmin"
    secret_key = "minioadmin"
    
    # Required for MinIO
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    use_path_style              = true
    skip_requesting_account_id  = true
  }
}

# Configure the MinIO provider
provider "minio" {
  minio_server   = "minio:9000"  # For GitHub Actions
  minio_server   = "minio:9000"  # For Docker Compose
  # minio_server = "localhost:9000"  # For local testing
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