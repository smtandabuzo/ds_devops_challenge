resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.environment
    Name        = "${var.app_name}-ecr-repo"
  }
}

# Output the repository URL
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
