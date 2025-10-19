# EC2 Launch Template for ECS Cluster
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "${var.app_name}-launch-template-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.small" # 2GB RAM for better performance
  key_name      = aws_key_pair.ec2_key_pair.key_name

  # Explicitly depend on the key pair
  depends_on = [aws_key_pair.ec2_key_pair]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_agent.name
  }
  network_interfaces {
    security_groups = [aws_security_group.ecs_instances.id]
  }
  user_data = base64encode(<<-EOT
    echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
  EOT
  )

  lifecycle {
    create_before_destroy = true
  }
}

# IAM roles and policies are defined in iam.tf
# Auto Scaling Group for ECS Instances
resource "aws_autoscaling_group" "ecs_asg" {
  # Add a name_prefix instead of name to allow for zero-downtime updates
  name_prefix         = "${var.app_name}-asg-"
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = 1
  max_size            = 1 # Keep it to 1 for free tier
  desired_capacity    = 1

  # Add health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Add termination policies
  termination_policies = ["OldestLaunchConfiguration", "OldestInstance", "Default"]

  # Add instance refresh to handle rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["tag"]
  }

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.app_name}-ecs-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = ""
    propagate_at_launch = true
  }

  # Add lifecycle to handle updates and replacements
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      # Ignore changes to desired_capacity as they are managed by auto-scaling
      desired_capacity,
      # Ignore changes to target_group_arns as they are managed by ECS
      target_group_arns
    ]
  }
}

# Security Group for ECS Instances
resource "aws_security_group" "ecs_instances" {
  name        = "${var.app_name}-ecs-instances-sg"
  description = "Security group for ECS instances"
  vpc_id      = local.vpc_id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH access (for debugging)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP/HTTPS traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow MinIO API and Console access
  ingress {
    from_port   = 9000
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-ecs-instances-sg"
  }
}

# IAM roles and policies are defined in iam.tf

# IAM instance role and policies are defined in iam.tf

# EC2 Key Pair is defined in key_pair.tf

# Data source for ECS-optimized AMI
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# MinIO ECS Task Definition
resource "aws_ecs_task_definition" "minio" {
  family                   = "${var.app_name}-minio"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "minio"
      image     = "minio/minio:latest"
      cpu       = 512
      memory    = 1024
      essential = true
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
      command = ["server", "/data", "--console-address", ":9001"]
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
      mountPoints = [
        {
          sourceVolume  = "minio-data"
          containerPath = "/data"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.app_name}-minio"
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  volume {
    name      = "minio-data"
    host_path = "/mnt/minio-data"
  }

  tags = {
    Environment = var.environment
    Application = "minio"
  }
}

# ECS Service for MinIO
resource "aws_ecs_service" "minio" {
  name            = "${var.app_name}-minio-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.minio.arn
  launch_type     = "EC2"
  desired_count   = 1

  service_registries {
    registry_arn   = aws_service_discovery_service.minio.arn
    container_name = "minio"
    container_port = 9001
  }

  # Load balancer configuration
  load_balancer {
    target_group_arn = aws_lb_target_group.minio.arn
    container_name   = "minio"
    container_port   = 9000
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
    aws_autoscaling_group.ecs_asg,
    aws_lb_target_group.minio
  ]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_lb_target_group" "minio" {
  name        = "${var.app_name}-minio-tg-new-${substr(md5(timestamp()), 0, 5)}"
  port        = 9000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    enabled             = true
    path                = "/minio/health/live"
    port                = "traffic-port"
{{ ... }}
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.app_name}-minio-tg"
  }
}

# ALB Listener Rule for MinIO - temporarily commented out for cleanup
# resource "aws_lb_listener_rule" "minio" {
#   listener_arn = aws_lb_listener.http_forward.arn
#   priority     = 200  # Changed from 100 to 200 to avoid conflict

#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.minio.arn
#   }

#   condition {
#     path_pattern {
#       values = ["/minio*", "/minio/*"]
#     }
#   }
# }
