resource "aws_ecs_task_definition" "minio" {
  family                   = "minio"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "minio"
      image     = "minio/minio:latest"
      essential = true
      command   = ["server", "/data", "--console-address", ":9001"]
      portMappings = [
        {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        },
        {
          containerPort = 9001
          hostPort      = 9001
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "MINIO_ROOT_USER"
          value = var.minio_access_key
        },
        {
          name  = "MINIO_ROOT_PASSWORD"
          value = var.minio_secret_key
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/minio"
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
      mountPoints = [
        {
          sourceVolume  = "minio-data"
          containerPath = "/data"
          readOnly      = false
        }
      ]
    }
  ])

  volume {
    name = "minio-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.minio_data.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }

  tags = {
    Environment = var.environment
    Application = "minio"
  }
}

resource "aws_ecs_service" "minio" {
  name            = "minio-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.minio.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = aws_subnet.public.*.id
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.minio.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]
}

resource "aws_efs_file_system" "minio_data" {
  creation_token = "minio-data"
  encrypted      = true

  tags = {
    Name = "${var.app_name}-minio-data"
  }
}

resource "aws_efs_mount_target" "minio_data" {
  count           = length(aws_subnet.public)
  file_system_id  = aws_efs_file_system.minio_data.id
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${var.app_name}-efs-sg"
  description = "Allow EFS access from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-efs-sg"
  }
}
