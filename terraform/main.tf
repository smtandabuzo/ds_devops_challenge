# Main configuration that doesn't fit into other files

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}
