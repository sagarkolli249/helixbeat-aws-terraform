###############################################################################
# HelixBeat – S3 Module (Data Tier)
# Provisions a set of application S3 buckets with:
#   • SSE-KMS encryption (CMK)
#   • Versioning enabled
#   • Intelligent-Tiering lifecycle
#   • Block Public Access
#   • Replication-ready policy
#   • Object Lock (Vault Lock) for compliance bucket
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

locals {
  buckets = {
    app-data = {
      description      = "Application data (primary object store)"
      object_lock      = false
      versioning       = true
      intelligent_tier = true
    }
    backups = {
      description      = "Application backups - vault locked"
      object_lock      = true
      versioning       = true
      intelligent_tier = false
    }
    artifacts = {
      description      = "Build artifacts and release packages"
      object_lock      = false
      versioning       = true
      intelligent_tier = false
    }
  }
}

# ---------------------------------------------------------------------------
# S3 Buckets
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = "${var.project}-${var.environment}-${each.key}-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  # Object Lock must be set at bucket creation
  object_lock_enabled = each.value.object_lock

  tags = merge(var.tags, {
    Name        = "${var.project}-${var.environment}-${each.key}"
    Description = each.value.description
  })
}

# ---------------------------------------------------------------------------
# Block Public Access on all buckets
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Server-side encryption (KMS CMK)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true # Reduces KMS API calls (cost optimization)
  }
}

# ---------------------------------------------------------------------------
# Versioning
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in local.buckets : k => v if v.versioning }

  bucket = aws_s3_bucket.this[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# Intelligent-Tiering (app-data bucket)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  for_each = { for k, v in local.buckets : k => v if v.intelligent_tier }

  bucket = aws_s3_bucket.this[each.key].id
  name   = "all-objects"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# ---------------------------------------------------------------------------
# Lifecycle Rules
# ---------------------------------------------------------------------------

# App-data: transition non-current versions, expire delete markers
resource "aws_s3_bucket_lifecycle_configuration" "app_data" {
  bucket = aws_s3_bucket.this["app-data"].id

  rule {
    id     = "noncurrent-version-transitions"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Backups: retain for 7 years, then expire
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.this["backups"].id

  rule {
    id     = "glacier-and-expire"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555 # 7 years
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Artifacts: clean up old versions after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.this["artifacts"].id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# Object Lock (backups bucket – COMPLIANCE mode, 35-day retain)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_object_lock_configuration" "backups" {
  bucket = aws_s3_bucket.this["backups"].id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 35
    }
  }
}

# ---------------------------------------------------------------------------
# Bucket Policies – enforce HTTPS and deny unencrypted PUT
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonHTTPS"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this[each.key].arn,
          "${aws_s3_bucket.this[each.key].arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "DenyUnencryptedPut"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.this[each.key].arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Sid       = "AllowEKSAndEC2Access"
        Effect    = "Allow"
        Principal = { AWS = var.allowed_role_arns }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.this[each.key].arn,
          "${aws_s3_bucket.this[each.key].arn}/*"
        ]
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------------------------------------------------------------------------
# VPC Endpoint Policy (limit S3 access to VPC only for data buckets)
# ---------------------------------------------------------------------------
# NOTE: Apply this policy to the S3 VPC Gateway Endpoint in the VPC module.
# The policy below restricts the endpoint to only allow access to
# HelixBeat-owned buckets, preventing data exfiltration.
resource "aws_vpc_endpoint_policy" "s3" {
  count           = var.s3_vpc_endpoint_id != "" ? 1 : 0
  vpc_endpoint_id = var.s3_vpc_endpoint_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowHelixBeatBuckets"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = concat(
          [for b in aws_s3_bucket.this : b.arn],
          [for b in aws_s3_bucket.this : "${b.arn}/*"]
        )
      },
      {
        # Allow access to AWS-owned service buckets (ECR layers, SSM, AL2/AL2023 repos).
        # Uses a prefix pattern instead of region-hardcoded names so this policy works
        # in all regions including newer ones (af-south-1, me-central-1, ap-southeast-5)
        # where the starport / amazonlinux bucket names differ or may not exist.
        Sid       = "AllowAWSServiceBuckets"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["s3:GetObject"]
        Resource = [
          "arn:aws:s3:::prod-*-starport-layer-bucket/*",
          "arn:aws:s3:::amazonlinux-2-repos-*/*",
          "arn:aws:s3:::amazonlinux.*amazonaws.com/*",
          "arn:aws:s3:::al2023-repos-*/*",
          "arn:aws:s3:::aws-ssm-*/*",
          "arn:aws:s3:::aws-windows-downloads-*/*"
        ]
      }
    ]
  })
}
