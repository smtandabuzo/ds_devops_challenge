resource "aws_lb" "main" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Environment = var.environment
    Application = var.app_name
  }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.app_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  depends_on = [aws_lb.main]
}

# MinIO Target Group
resource "aws_lb_target_group" "minio_tg" {
  name        = "${var.app_name}-minio-tg"
  port        = 9000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/minio/health/live"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  depends_on = [aws_lb.main]
}

resource "aws_lb_listener" "http_forward" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "No route matched the given path"
      status_code  = "404"
    }
  }
}

# Listener rule for main application
resource "aws_lb_listener_rule" "app" {
  listener_arn = aws_lb_listener.http_forward.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# Listener rule for MinIO
resource "aws_lb_listener_rule" "minio" {
  listener_arn = aws_lb_listener.http_forward.arn
  priority     = 99

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.minio_tg.arn
  }

  condition {
    path_pattern {
      values = ["/minio*", "/minio/*"]
    }
  }
}

# Uncomment this if you want to enable HTTPS
# resource "aws_lb_listener" "https_forward" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08"
#   certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app.arn
#   }
# }
