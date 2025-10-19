output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "minio_console_url" {
  description = "MinIO Console URL"
  value       = "http://${aws_lb.main.dns_name}:9001"
}

output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS Service Name"
  value       = aws_ecs_service.app.name
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = local.vpc_id
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = local.public_subnet_ids
}

output "security_group_id" {
  description = "Security Group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}
