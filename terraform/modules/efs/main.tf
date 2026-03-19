###############################################################################
# HelixBeat – EFS Module
# Encrypted, multi-AZ EFS filesystem for EKS persistent volumes.
# Used by: Kafka on EKS (broker logs), stateful apps needing shared storage.
# Includes EFS CSI driver IRSA role + access points per service.
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
# Security Group – EFS mount targets
# ---------------------------------------------------------------------------
resource "aws_security_group" "efs" {
  name        = "${var.project}-${var.environment}-efs-sg"
  description = "EFS mount target - allow NFS from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from EKS nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.eks_node_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-efs-sg" })
}

# ---------------------------------------------------------------------------
# EFS Filesystem
# ---------------------------------------------------------------------------
resource "aws_efs_file_system" "this" {
  creation_token   = "${var.project}-${var.environment}-efs"
  performance_mode = var.performance_mode # generalPurpose | maxIO
  throughput_mode  = var.throughput_mode  # bursting | provisioned | elastic
  encrypted        = true
  kms_key_id       = var.kms_key_arn

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-efs" })
}

# ---------------------------------------------------------------------------
# Mount Targets – one per private subnet (AZ)
# ---------------------------------------------------------------------------
resource "aws_efs_mount_target" "this" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# ---------------------------------------------------------------------------
# EFS Access Points (one per logical service)
# ---------------------------------------------------------------------------

# Kafka access point
resource "aws_efs_access_point" "kafka" {
  file_system_id = aws_efs_file_system.this.id

  root_directory {
    path = "/kafka"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "750"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-efs-kafka" })
}

# General app access point
resource "aws_efs_access_point" "app" {
  file_system_id = aws_efs_file_system.this.id

  root_directory {
    path = "/app"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "750"
    }
  }

  posix_user {
    gid = 1000
    uid = 1000
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-efs-app" })
}

# ---------------------------------------------------------------------------
# EFS CSI Driver IRSA role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "efs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:efs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "efs_csi" {
  name               = "${var.project}-${var.environment}-efs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

# ---------------------------------------------------------------------------
# EFS File System Policy (enforce encryption in transit)
# ---------------------------------------------------------------------------
resource "aws_efs_file_system_policy" "this" {
  file_system_id = aws_efs_file_system.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceInTransitEncryption"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "*"
        Resource  = aws_efs_file_system.this.arn
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}
