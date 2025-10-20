terraform {
  backend "s3" {
    # MinIO configuration
    endpoint                    = "http://minio:9000"  # Update with your MinIO endpoint
    bucket                      = "terraform-state"
    key                         = "terraform.tfstate"
    region                      = "us-east-1"  # Required but not used by MinIO
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
    
    # Use environment variables for credentials in production
    # access_key = "minioadmin"
    # secret_key = "minioadmin"
  }
}

# Enable MinIO provider
provider "minio" {
  minio_server   = "http://minio:9000"  # Update with your MinIO endpoint
  minio_user     = "minioadmin"         # Update with your MinIO access key
  minio_password = "minioadmin"         # Update with your MinIO secret key
}

# Create the bucket if it doesn't exist
resource "minio_s3_bucket" "terraform_state" {
  bucket = "terraform-state"
  acl    = "private"
  
  # Enable versioning for state files
  versioning {
    enabled = true
  }
  
  # Add lifecycle rule to clean up old state files
  lifecycle_rule {
    enabled = true
    
    expiration {
      days = 30
    }
    
    noncurrent_version_expiration {
      days = 14
    }
  }
}