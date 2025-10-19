# Route 53 Private Hosted Zone for service discovery
resource "aws_route53_zone" "private" {
  name = "${var.app_name}.local"

  vpc {
    vpc_id = local.vpc_id
  }

  tags = {
    Environment = var.environment
    Application = var.app_name
  }
}

# Output the zone ID for reference
output "route53_zone_id" {
  description = "The ID of the Route 53 private hosted zone"
  value       = aws_route53_zone.private.zone_id
}
