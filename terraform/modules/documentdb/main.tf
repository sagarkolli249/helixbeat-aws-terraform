###############################################################################
# HelixBeat – DocumentDB Module (MongoDB 5.0 API)
# Isolated Data Tier – 10.0.20.0/23 – 10.0.24.0/23
# Provisions:
#   • DocumentDB cluster (3-AZ, engine 5.0.0)
#   • Cluster instances (one per AZ)
#   • Dedicated subnet group + security group
#   • KMS encryption at rest
#   • TLS enforcement + audit logs
#   • Secrets Manager for credentials
#   • CloudWatch alarms
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Master password (Secrets Manager)
# ---------------------------------------------------------------------------
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "docdb_master" {
  name                    = "${var.project}/${var.environment}/documentdb/master"
  description             = "DocumentDB master credentials for ${var.project} ${var.environment}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 30

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "docdb_master" {
  secret_id = aws_secretsmanager_secret.docdb_master.id

  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    host     = aws_docdb_cluster.this.endpoint
    port     = 27017
    dbname   = var.database_name
    engine   = "mongo"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ---------------------------------------------------------------------------
# Subnet Group (data tier private subnets)
# ---------------------------------------------------------------------------
resource "aws_docdb_subnet_group" "this" {
  name        = "${var.project}-${var.environment}-docdb-subnet-group"
  subnet_ids  = var.subnet_ids
  description = "DocumentDB subnet group for ${var.project} ${var.environment}"

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-docdb-subnet-group" })
}

# ---------------------------------------------------------------------------
# Security Group – DocumentDB
# Only allow access from EKS node SG and EC2 SG on port 27017
# ---------------------------------------------------------------------------
resource "aws_security_group" "docdb" {
  name        = "${var.project}-${var.environment}-docdb-sg"
  description = "DocumentDB cluster – allow MongoDB from app tier only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MongoDB from EKS nodes"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-docdb-sg" })
}

# ---------------------------------------------------------------------------
# Cluster Parameter Group
# Enforces TLS + audit logging
# ---------------------------------------------------------------------------
resource "aws_docdb_cluster_parameter_group" "this" {
  family      = "docdb5.0"
  name        = "${var.project}-${var.environment}-docdb-params"
  description = "HelixBeat DocumentDB parameters"

  parameter {
    name  = "tls"
    value = "enabled"
  }

  parameter {
    name  = "audit_logs"
    value = "all"
  }

  parameter {
    name  = "ttl_monitor"
    value = "enabled"
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# DocumentDB Cluster
# ---------------------------------------------------------------------------
resource "aws_docdb_cluster" "this" {
  cluster_identifier              = "${var.project}-${var.environment}-docdb"
  engine                          = "docdb"
  engine_version                  = var.engine_version
  master_username                 = var.master_username
  master_password                 = random_password.master.result
  db_subnet_group_name            = aws_docdb_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.docdb.id]
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.this.name

  # Encryption
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Backup
  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${var.project}-${var.environment}-docdb-final"
  copy_tags_to_snapshot        = true

  # Logging → CloudWatch
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]

  # Deletion protection
  deletion_protection = var.deletion_protection

  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-docdb" })

  lifecycle {
    ignore_changes = [master_password]
  }
}

# ---------------------------------------------------------------------------
# DocumentDB Instances – one per AZ
# ---------------------------------------------------------------------------
resource "aws_docdb_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.project}-${var.environment}-docdb-${count.index}"
  cluster_identifier = aws_docdb_cluster.this.id
  instance_class     = var.instance_class

  auto_minor_version_upgrade  = true
  enable_performance_insights = var.enable_performance_insights

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-docdb-${count.index}"
    AZ   = "az-${count.index}"
  })
}

# ---------------------------------------------------------------------------
# CloudWatch Alarms
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${var.project}-${var.environment}-docdb-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DocDB"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "DocumentDB CPU above 80%"
  treat_missing_data  = "notBreaching"

  dimensions    = { DBClusterIdentifier = aws_docdb_cluster.this.cluster_identifier }
  alarm_actions = var.alarm_sns_topic_arns
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage" {
  alarm_name          = "${var.project}-${var.environment}-docdb-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeLocalStorage"
  namespace           = "AWS/DocDB"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5 GB in bytes
  alarm_description   = "DocumentDB free storage below 5 GB"
  treat_missing_data  = "notBreaching"

  dimensions    = { DBClusterIdentifier = aws_docdb_cluster.this.cluster_identifier }
  alarm_actions = var.alarm_sns_topic_arns
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "connections" {
  alarm_name          = "${var.project}-${var.environment}-docdb-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/DocDB"
  period              = 300
  statistic           = "Average"
  threshold           = 800
  alarm_description   = "DocumentDB connections above 800"
  treat_missing_data  = "notBreaching"

  dimensions    = { DBClusterIdentifier = aws_docdb_cluster.this.cluster_identifier }
  alarm_actions = var.alarm_sns_topic_arns
  tags          = var.tags
}
