provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.app_name
      ManagedBy   = "Terraform"
    }
  }
}

# Configure additional providers if needed (e.g., for different regions)
# provider "aws" {
#   alias  = "us-west-2"
#   region = "us-west-2"
# }
