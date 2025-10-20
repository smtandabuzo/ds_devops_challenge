# S3 Bucket for Analytics Data
resource "aws_s3_bucket" "analytics_data" {
  # Bucket naming with account ID to ensure uniqueness
  bucket = "${var.app_name}-analytics-data-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      bucket,
      tags,
      server_side_encryption_configuration
    ]
  }

  tags = {
    Name        = "${var.app_name}-analytics-data"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Enable versioning for data recovery
resource "aws_s3_bucket_versioning" "analytics_data_versioning" {
  bucket = aws_s3_bucket.analytics_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "analytics_data_encryption" {
  bucket = aws_s3_bucket.analytics_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3 encryption
    }
  }
}

# Configure lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "analytics_data_lifecycle" {
  bucket = aws_s3_bucket.analytics_data.id

  rule {
    id     = "analytics-data-lifecycle"
    status = "Enabled"

    # Transition to Standard-IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Expire non-current versions after 1 year
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# Block all public access to the bucket
resource "aws_s3_bucket_public_access_block" "analytics_data_block_public" {
  bucket = aws_s3_bucket.analytics_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Ensure bucket ownership controls are set
resource "aws_s3_bucket_ownership_controls" "analytics_data_ownership" {
  bucket = aws_s3_bucket.analytics_data.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# IAM Policy for accessing the analytics bucket
resource "aws_iam_policy" "analytics_bucket_access" {
  name        = "${var.app_name}-analytics-bucket-access"
  description = "Policy for accessing the analytics data bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [aws_s3_bucket.analytics_data.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = ["${aws_s3_bucket.analytics_data.arn}/*"]
      }
    ]
  })
}

# Attach the policy to the ECS task role
resource "aws_iam_role_policy_attachment" "ecs_task_analytics_access" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.analytics_bucket_access.arn
}

# Output the bucket name and ARN
output "analytics_bucket_name" {
  description = "Name of the analytics data bucket"
  value       = aws_s3_bucket.analytics_data.id
}

output "analytics_bucket_arn" {
  description = "ARN of the analytics data bucket"
  value       = aws_s3_bucket.analytics_data.arn
}
