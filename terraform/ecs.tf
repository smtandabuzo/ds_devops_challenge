resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = var.environment
    Name        = "${var.app_name}-ecs-cluster"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 30

  tags = {
    Application = var.app_name
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.app_name}-app"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = 256  # 0.25 vCPU
  memory                   = 512  # 512MB
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.app_name}-app" # Changed to avoid conflict with MinIO
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true
      environment = [
        {
          name  = "MINIO_ACCESS_KEY"
          value = var.minio_access_key
        },
        {
          name  = "MINIO_SECRET_KEY"
          value = var.minio_secret_key
        }
      ]
      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
    Application = var.app_name
  }
}

resource "aws_ecs_service" "app" {
  name                    = "${var.app_name}-service"
  cluster                 = aws_ecs_cluster.main.id
  task_definition         = aws_ecs_task_definition.app.arn
  desired_count           = var.app_count
  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"
  enable_execute_command  = true

  launch_type = "EC2"
  
  # For EC2 launch type, we don't need to specify network configuration
  # as it will use the EC2 instance's network settings

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "${var.app_name}-app" # Updated to match container name
    container_port   = var.app_port
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app.arn
  }

  depends_on = [
    aws_ecs_service.minio,
    aws_security_group.ecs_tasks,
    aws_lb_listener.http_forward,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]
}
