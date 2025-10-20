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

variable "app_port" {
  description = "Port exposed by the docker image"
  type        = number
  default     = 5000
}

variable "app_count" {
  description = "Number of docker containers to run"
  type        = number
  default     = 2
}

variable "minio_access_key" {
  description = "MinIO access key"
  type        = string
  default     = "minioadmin"
}

variable "minio_secret_key" {
  description = "MinIO secret key"
  type        = string
  default     = "minioadmin"
  sensitive   = true
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
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
