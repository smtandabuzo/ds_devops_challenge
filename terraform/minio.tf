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

# IAM Role for EC2 Instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.app_name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com"]
        }
      },
    ]
  })

  tags = {
    Name = "${var.app_name}-ecs-instance-role"
  }
}

# Attach necessary policies to the ECS instance role
resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_service_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# Additional inline policy for ECS operations
resource "aws_iam_role_policy" "ecs_operations" {
  name = "${var.app_name}-ecs-operations"
  role = aws_iam_role.ecs_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeTaskDefinition",
          "ecs:ListContainerInstances",
          "ecs:DescribeContainerInstances",
          "ecs:RegisterContainerInstance",
          "ecs:DeregisterContainerInstance",
          "ecs:DiscoverPollEndpoint",
          "ecs:Submit*",
          "ecs:Poll",
          "ecs:StartTask",
          "ecs:StartTelemetrySession"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceAttribute"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "${var.app_name}-ecs-agent"
  role = aws_iam_role.ecs_instance_role.name
}
# Auto Scaling Group for ECS Instances
resource "aws_autoscaling_group" "ecs_asg" {
  # Add a name_prefix instead of name to allow for zero-downtime updates
  name_prefix          = "${var.app_name}-asg-"
  vpc_zone_identifier  = aws_subnet.public[*].id
  min_size             = 1
  max_size             = 1 # Keep it to 1 for free tier
  desired_capacity     = 1
  
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
      target_group_arns,
      # Ignore changes to load_balancers as they are managed by ECS
      load_balancers,
    ]
  }
  
  # Add depends_on to ensure proper cleanup
  depends_on = [
    aws_launch_template.ecs_launch_template,
    aws_iam_instance_profile.ecs_agent
  ]
}

data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# Security Group for ECS Instances
resource "aws_security_group" "ecs_instances" {
  name        = "${var.app_name}-ecs-instances-sg"
  description = "Security group for ECS instances"
  vpc_id      = aws_vpc.main.id

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

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow MinIO API access
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MinIO API"
  }

  # Allow MinIO Console access
  ingress {
    from_port   = 9001
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MinIO Console"
  }

  # Allow all traffic within the security group
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  tags = {
    Name = "${var.app_name}-ecs-instances-sg"
  }
}

# MinIO EBS Volume
resource "aws_ebs_volume" "minio_data" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = 20 # GB
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.app_name}-minio-data"
  }
}

resource "aws_ecs_task_definition" "minio" {
  family                   = "minio"
  network_mode             = "bridge" # Using bridge mode for EC2 launch type
  requires_compatibilities = ["EC2"]
  cpu                      = 256
  memory                   = 768 # Reduced to 768MB to fit t3.small
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  volume {
    name      = "minio-data"
    host_path = "/mnt/minio-data"
  }

  container_definitions = jsonencode([
    {
      name      = "minio"
      image     = "minio/minio:latest"
      essential = true
      command   = ["server", "/data", "--console-address", ":9001"]
      portMappings = [
        {
          containerPort = 9000
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
}

resource "aws_ecs_service" "minio" {
  name            = "minio-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.minio.arn
  launch_type     = "EC2"
  desired_count   = 1

  # Service discovery
  service_registries {
    registry_arn   = aws_service_discovery_service.minio.arn
    container_name = "minio"
    container_port = 9001
  }

  # Load balancer configuration - temporarily commented out for target group recreation
  # load_balancer {
  #   target_group_arn = aws_lb_target_group.minio.arn
  #   container_name   = "minio"
  #   container_port   = 9001
  # }

  # Ensure the EBS volume is attached before starting the service
  depends_on = [
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy,
    aws_autoscaling_group.ecs_asg,
    aws_lb_target_group.minio
  ]

  # Add a lifecycle rule to ignore changes to the task definition
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_lb_target_group" "minio" {
  name        = "${var.app_name}-minio-tg-new-${substr(md5(timestamp()), 0, 5)}" # Added 'new' to the name to avoid conflicts
  port        = 9001
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/minio/health/live"
    port                = "traffic-port"
    protocol            = "HTTP"
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
