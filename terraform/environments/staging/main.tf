###############################################################################
# HelixBeat – Staging Environment
# Production-like sizing for full integration and load testing.
#
# Same circular-dependency fix as dev:
#   route53 module called with zone inputs only (no ALB).
#   Alias records, health check, and internal CNAMEs are inline resources.
###############################################################################

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket         = "helixbeat-tfstate-staging"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "helixbeat-tfstate-lock-staging"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  environment  = "staging"
  cluster_name = "helixbeat-${local.environment}"

  common_tags = {
    Project      = "helixbeat"
    Environment  = local.environment
    ManagedBy    = "terraform"
    Owner        = "platform-team"
    BackupPolicy = "helixbeat-daily"
  }
}

# -----------------------------------------------------------------------------
# VPC  (10.20.0.0/16 – non-overlapping with dev)
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project            = "helixbeat"
  environment        = local.environment
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  cluster_name       = local.cluster_name
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------
module "security" {
  source = "../../modules/security"

  environment           = local.environment
  alert_email_addresses = var.alert_email_addresses
  alarm_sns_topic_arns  = []
  tags                  = local.common_tags
}

# -----------------------------------------------------------------------------
# Route 53 – zones only (alias records inline below to break the cycle)
# -----------------------------------------------------------------------------
module "route53" {
  source = "../../modules/route53"

  project              = "helixbeat"
  environment          = local.environment
  domain_name          = var.domain_name
  vpc_id               = module.vpc.vpc_id
  internal_dns_records = {}
  tags                 = local.common_tags
}

# -----------------------------------------------------------------------------
# ACM
# -----------------------------------------------------------------------------
module "acm" {
  source = "../../modules/acm"

  project     = "helixbeat"
  environment = local.environment

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}", var.domain_name]
  route53_zone_id           = module.route53.public_zone_id
  tags                      = local.common_tags

  depends_on = [module.route53]
}

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  project     = "helixbeat"
  environment = local.environment

  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  public_subnet_ids = module.vpc.public_subnet_ids

  acm_certificate_arn        = module.acm.certificate_arn
  waf_web_acl_arn            = module.security.waf_web_acl_arn
  health_check_path          = "/health"
  enable_deletion_protection = true

  access_logs_bucket        = "helixbeat-${local.environment}-alb-logs-${data.aws_caller_identity.current.account_id}"
  create_access_logs_bucket = true

  alarm_sns_topic_arns = [module.security.security_alerts_sns_topic_arn]
  tags                 = local.common_tags

  depends_on = [module.acm]
}

# -----------------------------------------------------------------------------
# Route 53 – Alias records and health check (inline)
# -----------------------------------------------------------------------------
resource "aws_route53_record" "apex" {
  zone_id = module.route53.public_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wildcard" {
  zone_id = module.route53.public_zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_health_check" "primary" {
  fqdn              = module.alb.alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  enable_sni        = true

  tags = merge(local.common_tags, { Name = "helixbeat-${local.environment}-hc-primary" })
}

# -----------------------------------------------------------------------------
# EKS (production-like sizing)
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  system_node_instance_types = ["m5.large"]
  system_node_desired        = 2
  system_node_min            = 2
  system_node_max            = 4

  app_node_instance_types = ["m5.xlarge"]
  app_node_desired        = 2
  app_node_min            = 2
  app_node_max            = 8

  ecr_repositories = var.ecr_repositories
  tags             = local.common_tags
}

# -----------------------------------------------------------------------------
# IAM / IRSA
# -----------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  cluster_name           = local.cluster_name
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_provider_url      = module.eks.cluster_oidc_issuer_url
  monitoring_bucket_name = "helixbeat-${local.environment}-monitoring-${data.aws_caller_identity.current.account_id}"
  general_kms_key_arn    = module.security.general_kms_key_arn
  tags                   = local.common_tags
}

# -----------------------------------------------------------------------------
# EFS
# -----------------------------------------------------------------------------
module "efs" {
  source = "../../modules/efs"

  project     = "helixbeat"
  environment = local.environment

  vpc_id                      = module.vpc.vpc_id
  private_subnet_ids          = module.vpc.private_subnet_ids
  eks_node_security_group_ids = [module.eks.node_security_group_id]
  kms_key_arn                 = module.security.general_kms_key_arn
  oidc_provider_arn           = module.eks.oidc_provider_arn
  oidc_provider_url           = module.eks.cluster_oidc_issuer_url
  tags                        = local.common_tags
}

# -----------------------------------------------------------------------------
# EC2 (production-like: m5.xlarge + min 2)
# -----------------------------------------------------------------------------
module "ec2" {
  source = "../../modules/ec2"

  project     = "helixbeat"
  environment = local.environment

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  kms_key_arn           = module.security.general_kms_key_arn

  ami_id               = var.ec2_ami_id
  instance_type        = "m5.xlarge"
  root_volume_size_gb  = 100
  asg_min_size         = 2
  asg_max_size         = 8
  asg_desired_capacity = 2
  target_group_arns    = [module.alb.default_target_group_arn]

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# DocumentDB (production-like: r6g.xlarge, 3 instances, deletion_protection)
# -----------------------------------------------------------------------------
module "documentdb" {
  source = "../../modules/documentdb"

  project     = "helixbeat"
  environment = local.environment

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_security_group_ids = [
    module.eks.node_security_group_id,
    module.ec2.security_group_id,
  ]

  kms_key_arn           = module.security.general_kms_key_arn
  engine_version        = "5.0.0"
  instance_class        = "db.r6g.xlarge"
  instance_count        = 3
  backup_retention_days = 35
  deletion_protection   = true

  alarm_sns_topic_arns = [module.security.security_alerts_sns_topic_arn]
  tags                 = local.common_tags
}

# -----------------------------------------------------------------------------
# Route 53 – Internal CNAME for DocumentDB (inline)
# -----------------------------------------------------------------------------
resource "aws_route53_record" "documentdb_internal" {
  zone_id = module.route53.private_zone_id
  name    = "documentdb.internal.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = [module.documentdb.cluster_endpoint]
}

# -----------------------------------------------------------------------------
# S3
# -----------------------------------------------------------------------------
module "s3" {
  source = "../../modules/s3"

  project     = "helixbeat"
  environment = local.environment
  aws_region  = var.aws_region

  kms_key_arn = module.security.general_kms_key_arn

  allowed_role_arns = [
    module.iam.monitoring_role_arn,
    module.ec2.instance_role_arn,
  ]

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# AWS Backup
# -----------------------------------------------------------------------------
module "backup" {
  source = "../../modules/backup"

  project     = "helixbeat"
  environment = local.environment

  kms_key_arn = module.security.general_kms_key_arn

  documentdb_cluster_arns = [
    "arn:aws:docdb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster:${module.documentdb.cluster_id}"
  ]

  efs_file_system_arns = [module.efs.file_system_arn]
  alarm_sns_topic_arn  = module.security.security_alerts_sns_topic_arn
  tags                 = local.common_tags
}
