###############################################################################
# HelixBeat – EC2 Module (Migrated VMs)
# Private Application Tier – SSM-only access (no SSH/RDP),
# IMDSv2 enforced, Inspector v2 enabled, gp3 EBS encryption.
# Produces a reusable Launch Template for ASG-based deployments.
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# IAM Instance Role (SSM + CloudWatch + Inspector)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ec2" {
  name = "${var.project}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# SSM Session Manager (replaces SSH)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Inspector v2 (vulnerability scanning)
resource "aws_iam_role_policy_attachment" "inspector" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonInspector2ManagedCisPolicy"
}

# ECR read (pull container images if needed)
resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Secrets Manager read (for app config)
resource "aws_iam_role_policy" "secrets" {
  name = "read-secrets"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/${var.environment}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = var.tags
}

# ---------------------------------------------------------------------------
# Security Group – EC2 instances (app tier)
# ---------------------------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.environment}-ec2-sg"
  description = "EC2 app instances – inbound from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  ingress {
    description = "Node-to-node (internal)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All outbound (SSM, ECR, S3 via VPC endpoints)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-ec2-sg" })
}

# ---------------------------------------------------------------------------
# Launch Template (IMDSv2 enforced, gp3 EBS, no public IP)
# ---------------------------------------------------------------------------
resource "aws_launch_template" "this" {
  name_prefix   = "${var.project}-${var.environment}-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  # IMDSv2 – hop limit 1 prevents container metadata leakage
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 mandatory
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Root volume – encrypted gp3
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size_gb
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
      throughput            = 125
      iops                  = 3000
    }
  }

  # No public IPs
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
  }

  monitoring {
    enabled = true # Detailed CloudWatch monitoring
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    project     = var.project
    environment = var.environment
    region      = data.aws_region.current.name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name         = "${var.project}-${var.environment}-app"
      BackupPolicy = "${var.project}-daily"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name         = "${var.project}-${var.environment}-app-vol"
      BackupPolicy = "${var.project}-daily"
    })
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Auto Scaling Group
# ---------------------------------------------------------------------------
resource "aws_autoscaling_group" "this" {
  name                      = "${var.project}-${var.environment}-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = var.target_group_arns
  health_check_type         = "ELB"
  health_check_grace_period = 120

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 75
    }
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = "${var.project}-${var.environment}-app" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# ---------------------------------------------------------------------------
# Inspector v2 enablement
# ---------------------------------------------------------------------------
resource "aws_inspector2_enabler" "this" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR"]
}

# ---------------------------------------------------------------------------
# SSM Patch Manager baseline
# ---------------------------------------------------------------------------
resource "aws_ssm_patch_baseline" "amazon_linux" {
  name             = "${var.project}-${var.environment}-al2-baseline"
  description      = "HelixBeat Amazon Linux 2 patch baseline"
  operating_system = "AMAZON_LINUX_2"

  approval_rule {
    approve_after_days  = 7
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix", "Enhancement"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important", "Medium"]
    }
  }

  tags = var.tags
}

resource "aws_ssm_maintenance_window" "this" {
  name     = "${var.project}-${var.environment}-patch-window"
  schedule = "cron(0 2 ? * SUN *)" # Sundays 2 AM UTC
  duration = 3
  cutoff   = 1

  tags = var.tags
}

resource "aws_ssm_maintenance_window_target" "this" {
  window_id     = aws_ssm_maintenance_window.this.id
  name          = "all-instances"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Project"
    values = [var.project]
  }
}
