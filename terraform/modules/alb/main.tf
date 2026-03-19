###############################################################################
# HelixBeat – ALB Module (Public Tier)
# Provisions:
#   • Application Load Balancer (internet-facing, multi-AZ)
#   • HTTPS listener (443) with ACM cert, HTTP→HTTPS redirect
#   • WAFv2 Web ACL association
#   • Shield Advanced (optional)
#   • Security group with strict ingress (443 only from internet)
#   • Default target group for EKS ingress controller
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Security Group – ALB
# Only allow 80 (redirect) and 443 from internet; all else denied.
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb-sg"
  description = "ALB security group – HTTPS only from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward to EKS nodes and EC2"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-alb-sg" })
}

# ---------------------------------------------------------------------------
# ALB – internet-facing, deployed in public subnets
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true
  enable_http2                     = true
  drop_invalid_header_fields       = true # Security: drop malformed headers

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = "${var.project}-${var.environment}-alb"
    enabled = true
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-alb" })
}

# ---------------------------------------------------------------------------
# Default Target Group (for EKS AWS Load Balancer Controller)
# ---------------------------------------------------------------------------
resource "aws_lb_target_group" "default" {
  name        = "${var.project}-${var.environment}-default-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for EKS pod-level routing

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-default-tg" })
}

# ---------------------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------------------

# HTTP → HTTPS redirect
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener with ACM cert
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # TLS 1.3 preferred, min 1.2
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}

# ---------------------------------------------------------------------------
# WAFv2 association
# ---------------------------------------------------------------------------
resource "aws_wafv2_web_acl_association" "this" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.waf_web_acl_arn
}

# ---------------------------------------------------------------------------
# S3 bucket for ALB access logs
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "access_logs" {
  count         = var.create_access_logs_bucket ? 1 : 0
  bucket        = var.access_logs_bucket
  force_destroy = false

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-alb-logs" })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count  = var.create_access_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count  = var.create_access_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # ALB logs require AES256, not KMS
    }
  }
}

# ALB requires a specific bucket policy to write access logs
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "access_logs" {
  count  = var.create_access_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.access_logs_bucket}/${var.project}-${var.environment}-alb/AWSLogs/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.access_logs_bucket}/${var.project}-${var.environment}-alb/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.access_logs_bucket}"
      }
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count  = var.create_access_logs_bucket ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Alarms – ALB health
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project}-${var.environment}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB target 5XX errors exceeding threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = var.alarm_sns_topic_arns
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  alarm_name          = "${var.project}-${var.environment}-alb-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "p99"
  threshold           = 2 # 2 second p99
  alarm_description   = "ALB p99 latency above 2s"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = var.alarm_sns_topic_arns
  tags          = var.tags
}
