# ECR Repository for MinIO
resource "aws_ecr_repository" "minio" {
  name                 = "${var.app_name}-minio"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.environment
    Name        = "${var.app_name}-minio-ecr-repo"
  }
}

# Output the MinIO repository URL
output "minio_ecr_repository_url" {
  value = aws_ecr_repository.minio.repository_url
}
