###############################################################################
# HelixBeat – AWS Backup Module
# Centralised backup policy for:
#   • EKS EBS volumes (gp3 PVCs)
#   • EFS filesystem
#   • DocumentDB cluster
#   • EC2 instances
# Vault Lock prevents accidental/malicious deletion (35-day minimum retain).
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
# KMS key for backup vault encryption
# ---------------------------------------------------------------------------
resource "aws_backup_vault" "this" {
  name        = "${var.project}-${var.environment}-backup-vault"
  kms_key_arn = var.kms_key_arn

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-backup-vault" })
}

# ---------------------------------------------------------------------------
# Vault Lock (Compliance mode – prevents any deletion for 35 days)
# ---------------------------------------------------------------------------
resource "aws_backup_vault_lock_configuration" "this" {
  backup_vault_name   = aws_backup_vault.this.name
  changeable_for_days = 3       # 3 days to reconfigure before lock is permanent
  min_retention_days  = 35
  max_retention_days  = 2555    # 7 years maximum
}

# ---------------------------------------------------------------------------
# IAM Role – AWS Backup Service
# ---------------------------------------------------------------------------
resource "aws_iam_role" "backup" {
  name = "${var.project}-${var.environment}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# EFS needs additional permissions
resource "aws_iam_role_policy_attachment" "backup_efs" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientFullAccess"
}

# ---------------------------------------------------------------------------
# Backup Plans
# ---------------------------------------------------------------------------

# Daily backups (35-day retention) – for DocumentDB, EFS, EBS
resource "aws_backup_plan" "daily" {
  name = "${var.project}-${var.environment}-daily-backup"

  rule {
    rule_name         = "daily-35d"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 3 * * ? *)"   # 3 AM UTC daily
    start_window      = 60
    completion_window = 180

    lifecycle {
      cold_storage_after = 30   # Move to cold storage after 30 days
      delete_after       = 35
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.this.arn
      lifecycle {
        delete_after = 35
      }
    }
  }

  rule {
    rule_name         = "weekly-90d"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 4 ? * 1 *)"   # Every Sunday 4 AM UTC
    start_window      = 60
    completion_window = 360

    lifecycle {
      cold_storage_after = 7
      delete_after       = 90
    }
  }

  rule {
    rule_name         = "monthly-1yr"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 5 1 * ? *)"   # 1st of each month 5 AM UTC
    start_window      = 60
    completion_window = 480

    lifecycle {
      cold_storage_after = 1
      delete_after       = 365
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Backup Selections (tag-based)
# Resources tagged with BackupPolicy=helixbeat-daily are included.
# ---------------------------------------------------------------------------
resource "aws_backup_selection" "tagged_resources" {
  name         = "${var.project}-${var.environment}-tagged-resources"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.daily.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "BackupPolicy"
    value = "${var.project}-daily"
  }
}

# Explicit selection for DocumentDB (tag-based backup doesn't always work)
resource "aws_backup_selection" "documentdb" {
  count        = length(var.documentdb_cluster_arns) > 0 ? 1 : 0
  name         = "${var.project}-${var.environment}-documentdb"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.daily.id

  resources = var.documentdb_cluster_arns
}

# Explicit selection for EFS
resource "aws_backup_selection" "efs" {
  count        = length(var.efs_file_system_arns) > 0 ? 1 : 0
  name         = "${var.project}-${var.environment}-efs"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.daily.id

  resources = var.efs_file_system_arns
}

# ---------------------------------------------------------------------------
# SNS notifications for backup job status
# ---------------------------------------------------------------------------
resource "aws_backup_vault_notifications" "this" {
  backup_vault_name   = aws_backup_vault.this.name
  sns_topic_arn       = var.alarm_sns_topic_arn
  backup_vault_events = [
    "BACKUP_JOB_FAILED",
    "RESTORE_JOB_FAILED",
    "BACKUP_VAULT_LOCK_CONFIGURATION_CHANGED",
  ]
}
