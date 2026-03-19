###############################################################################
# HelixBeat – Dev Environment
# Full Azure → AWS architecture:
#   Public:  Route53 + ACM + ALB (WAF)
#   App:     EKS + EC2 + ECR + IAM/IRSA
#   Data:    DocumentDB + S3 + EFS + Kafka-on-EKS (Strimzi)
#   Security: KMS + Secrets Manager + GuardDuty + SecurityHub + CloudTrail
#   Backup:  AWS Backup (Vault Lock, 35d retain)
#
# Dependency ordering (no cycles):
#   vpc, security                                       (no module deps)
#   route53    -> vpc                                   (zone only, no ALB)
#   acm        -> route53 (public_zone_id)
#   alb        -> acm, security, vpc
#   eks        -> vpc
#   iam        -> eks
#   efs        -> vpc, eks, security
#   ec2        -> vpc, alb, security
#   documentdb -> vpc, eks, ec2, security
#   s3         -> security, iam, ec2
#   backup     -> security, documentdb, efs
#   (inline)   aws_route53_record.*  -> alb, route53
#   (inline)   aws_route53_record.documentdb_internal -> documentdb, route53
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
    bucket         = "helixbeat-tfstate-dev"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "helixbeat-tfstate-lock-dev"
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
  environment  = "dev"
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
# VPC  (10.10.0.0/16)
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
# Security (GuardDuty + WAF + CloudTrail + Config + SecurityHub + KMS)
# -----------------------------------------------------------------------------
module "security" {
  source = "../../modules/security"

  environment           = local.environment
  alert_email_addresses = var.alert_email_addresses
  alarm_sns_topic_arns  = []
  tags                  = local.common_tags
}

# -----------------------------------------------------------------------------
# Route 53 – hosted zones ONLY (no ALB inputs to avoid circular dependency)
# Alias records and internal CNAMEs are inline resources below.
# Cycle that is broken:
#   route53 --(internal_dns_records)--> documentdb --> ec2 --> alb --> acm --> route53
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
# ACM – wildcard TLS certificate (DNS-validated via Route 53)
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
# ALB (internet-facing + HTTPS only + WAFv2 + access logs)
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
  enable_deletion_protection = false

  access_logs_bucket        = "helixbeat-${local.environment}-alb-logs-${data.aws_caller_identity.current.account_id}"
  create_access_logs_bucket = true

  alarm_sns_topic_arns = [module.security.security_alerts_sns_topic_arn]
  tags                 = local.common_tags

  depends_on = [module.acm]
}

# -----------------------------------------------------------------------------
# Route 53 – Public A (apex + wildcard) alias records, inline after ALB
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
# EKS (private cluster + system/app node groups + IRSA + ECR)
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  system_node_instance_types = ["m5.large"]
  system_node_desired        = 2
  system_node_min            = 1
  system_node_max            = 3

  app_node_instance_types = ["m5.large"]
  app_node_desired        = 1
  app_node_min            = 1
  app_node_max            = 5

  ecr_repositories = var.ecr_repositories
  tags             = local.common_tags
}

# -----------------------------------------------------------------------------
# IAM / IRSA roles
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
# EFS (Kafka-on-EKS broker storage + app shared volumes)
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
# EC2 (migrated VMs + IMDSv2 + SSM + Inspector v2 + gp3 encrypted + ASG)
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
  instance_type        = "m5.large"
  root_volume_size_gb  = 50
  asg_min_size         = 1
  asg_max_size         = 4
  asg_desired_capacity = 1
  target_group_arns    = [module.alb.default_target_group_arn]

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# DocumentDB (MongoDB 5.0 + 3 AZ + TLS enforced + SCRAM + 35d backup)
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
  instance_class        = "db.r6g.large"
  instance_count        = 3
  backup_retention_days = 35
  deletion_protection   = false

  alarm_sns_topic_arns = [module.security.security_alerts_sns_topic_arn]
  tags                 = local.common_tags
}

# -----------------------------------------------------------------------------
# Route 53 – Internal CNAME for DocumentDB (inline to avoid cycle)
# -----------------------------------------------------------------------------
resource "aws_route53_record" "documentdb_internal" {
  zone_id = module.route53.private_zone_id
  name    = "documentdb.internal.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = [module.documentdb.cluster_endpoint]
}

# -----------------------------------------------------------------------------
# S3 (app-data + backups + artifacts – SSE-KMS + versioning + object lock)
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
# AWS Backup (Vault Lock + daily/weekly/monthly plans)
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
