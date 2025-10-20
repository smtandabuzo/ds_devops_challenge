variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "ds-devops-app"
}

# Standard tags to be applied to all resources
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "ds-devops-app"
    Owner       = "devops-team"
  }
}

# Custom tags to be merged with default tags
variable "resource_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Merge default and custom tags
locals {
  common_tags = merge(
    var.default_tags,
    var.resource_tags,
    {
      Terraform   = "true"
      Environment = var.environment
      Application = var.app_name
    }
  )
}

variable "app_port" {
  description = "Port exposed by the docker image"
  type        = number
  default     = 5000

  validation {
    condition     = var.app_port > 0 && var.app_port <= 65535
    error_message = "The app_port must be a valid port number between 1 and 65535."
  }
}

variable "app_count" {
  description = "Number of docker containers to run"
  type        = number
  default     = 2

  validation {
    condition     = var.app_count > 0 && var.app_count <= 10
    error_message = "The app_count must be between 1 and 10."
  }
}

variable "minio_access_key" {
  description = "MinIO access key"
  type        = string
  default     = "minioadmin"

  validation {
    condition     = length(var.minio_access_key) >= 3 && length(var.minio_access_key) <= 20
    error_message = "The MinIO access key must be between 3 and 20 characters long."
  }

  # Mark as sensitive to prevent accidental exposure in logs
  sensitive = true
}

variable "minio_secret_key" {
  description = "MinIO secret key"
  type        = string
  default     = "minioadmin"

  validation {
    condition     = length(var.minio_secret_key) >= 8
    error_message = "The MinIO secret key must be at least 8 characters long for security."
  }

  sensitive = true
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "v1.0.0" # Default to a specific version

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+$", var.image_tag))
    error_message = "The image_tag can only contain alphanumeric characters, dots, underscores, and hyphens."
  }

  validation {
    condition     = var.image_tag != ""
    error_message = "The image_tag cannot be empty."
  }
}
variable "use_existing_vpc" {
  description = "Whether to use an existing VPC or create a new one"
  type        = bool
  default     = true
}

variable "create_igw" {
  description = "Whether to create an Internet Gateway if one doesn't exist"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}
