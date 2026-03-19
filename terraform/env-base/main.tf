###############################################################################
# HelixBeat – env-base orchestration module
#
# Single source of truth for the full infrastructure stack.
# Called by every environments/{env}-{country}/main.tf.
#
# Module toggles
# ──────────────
# Each optional module is guarded by  count = local.mod.X ? 1 : 0
# Wherever one module's output feeds into another, the reference is wrapped in
#   try(one(module.X[*].output_name), <safe_fallback>)
# so that Terraform never errors when a dependency module is disabled.
#
# Provider and backend are defined in the calling environment, NOT here.
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  # ── Canonical naming ──────────────────────────────────────────────────────
  name_prefix  = "helixbeat-${var.environment}-${var.country_code}"
  cluster_name = local.name_prefix

  # ── Common resource tags ──────────────────────────────────────────────────
  common_tags = merge(
    {
      Project      = "helixbeat"
      Environment  = var.environment
      Country      = var.country_code
      Region       = var.aws_region
      ManagedBy    = "terraform"
      Owner        = "platform-team"
      BackupPolicy = "helixbeat-daily"
    },
    var.tags
  )

  # ── Module enable/disable flags (shorthand) ───────────────────────────────
  mod = var.modules

  # ── Region-capability map ─────────────────────────────────────────────────
  # Drives region-specific instance types, feature availability, and endpoint
  # exclusions. Add a new entry when onboarding a new AWS region.
  region_defaults = {
    # Mature / full-featured regions
    "us-east-1"      = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "us-east-2"      = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "us-west-1"      = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "us-west-2"      = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "eu-west-1"      = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "eu-west-2"      = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "eu-central-1"   = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "ap-southeast-1" = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "ap-southeast-2" = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "ap-south-1"     = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "ap-northeast-1" = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    "ca-central-1"   = { instance_family = "m5", docdb_class = "db.r6g", efs_mode = "elastic", sh_standards = true, gd_advanced = true, excl_ep = [] }
    # Newer / smaller regions – limited service availability
    "af-south-1"     = { instance_family = "m6i", docdb_class = "db.r5", efs_mode = "elastic", sh_standards = false, gd_advanced = false, excl_ep = ["autoscaling"] }
    "me-central-1"   = { instance_family = "m6i", docdb_class = "db.r5", efs_mode = "elastic", sh_standards = false, gd_advanced = false, excl_ep = ["autoscaling"] }
    "ap-southeast-3" = { instance_family = "m6i", docdb_class = "db.r5", efs_mode = "elastic", sh_standards = false, gd_advanced = false, excl_ep = [] }
    "ap-southeast-5" = { instance_family = "m6i", docdb_class = "db.r5", efs_mode = "bursting", sh_standards = false, gd_advanced = false, excl_ep = ["autoscaling", "elasticloadbalancing"] }
  }

  # Resolved region config (safe fallback for unknown regions)
  _rc = lookup(local.region_defaults, var.aws_region, {
    instance_family = "m6i"
    docdb_class     = "db.r5"
    efs_mode        = "bursting"
    sh_standards    = false
    gd_advanced     = false
    excl_ep         = []
  })

  region_instance_family = local._rc.instance_family
  region_docdb_class     = local._rc.docdb_class
  region_efs_mode        = var.efs_throughput_mode != null ? var.efs_throughput_mode : local._rc.efs_mode
  region_sh_standards    = var.enable_securityhub_standards != null ? var.enable_securityhub_standards : local._rc.sh_standards
  region_gd_advanced     = var.enable_guardduty_advanced != null ? var.enable_guardduty_advanced : local._rc.gd_advanced
  region_excl_ep         = var.vpc_excluded_endpoints != null ? var.vpc_excluded_endpoints : local._rc.excl_ep

  system_node_types = var.system_node_instance_types != null ? var.system_node_instance_types : ["${local.region_instance_family}.large"]
  app_node_types    = var.app_node_instance_types != null ? var.app_node_instance_types : ["${local.region_instance_family}.large"]

  # ── Safe cross-module output references ───────────────────────────────────
  # Split into individual locals (NOT a single object) to avoid evaluation
  # cycles. Terraform evaluates each local as a unit; a single aggregated
  # object that references both upstream and downstream modules forces all
  # contributing modules to resolve before any module can receive its inputs.
  #
  # Tier 1 – upstream modules (ALB, EKS). These are inputs to EC2/IAM/EFS/DB.
  alb_dns    = try(one(module.alb[*].alb_dns_name), "")
  alb_zone   = try(one(module.alb[*].alb_zone_id), "")
  alb_sg     = try(one(module.alb[*].security_group_id), "")
  alb_tg_arn = try(one(module.alb[*].default_target_group_arn), "")

  eks_oidc_arn = try(one(module.eks[*].oidc_provider_arn), "")
  eks_oidc_url = try(one(module.eks[*].cluster_oidc_issuer_url), "")
  eks_node_sg  = try(one(module.eks[*].node_security_group_id), "")

  # Tier 2 – downstream module outputs. Used only in outputs.tf and backup.
  # Never used as inputs to other modules (which would create a cycle).
  ec2_sg       = try(one(module.ec2[*].security_group_id), "")
  ec2_role_arn = try(one(module.ec2[*].instance_role_arn), "")

  iam_monitor_arn = try(one(module.iam[*].monitoring_role_arn), "")
  iam_monitor_bkt = try(one(module.iam[*].monitoring_bucket_name), "")

  docdb_endpoint = try(one(module.documentdb[*].cluster_endpoint), "")
  docdb_id       = try(one(module.documentdb[*].cluster_id), "")

  efs_arn      = try(one(module.efs[*].file_system_arn), "")
  efs_id       = try(one(module.efs[*].file_system_id), "")
  efs_kafka_ap = try(one(module.efs[*].kafka_access_point_id), "")
}

# =============================================================================
# ALWAYS-ON MODULES
# VPC, Security, Route53 are foundational and cannot be disabled.
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../modules/vpc"

  project            = "helixbeat"
  environment        = "${var.environment}-${var.country_code}"
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  cluster_name       = local.cluster_name
  excluded_endpoints = local.region_excl_ep
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# Security (GuardDuty · WAF · CloudTrail · Config · SecurityHub · KMS)
# -----------------------------------------------------------------------------
module "security" {
  source = "../modules/security"

  environment                         = "${var.environment}-${var.country_code}"
  alert_email_addresses               = var.alert_email_addresses
  alarm_sns_topic_arns                = []
  enable_securityhub_cis_standard     = local.region_sh_standards
  enable_securityhub_fsbp_standard    = local.region_sh_standards
  enable_guardduty_kubernetes         = local.region_gd_advanced
  enable_guardduty_malware_protection = local.region_gd_advanced
  tags                                = local.common_tags
}

# -----------------------------------------------------------------------------
# Route 53 – hosted zones only (no ALB inputs; alias records inline below)
# -----------------------------------------------------------------------------
module "route53" {
  source = "../modules/route53"

  project              = "helixbeat"
  environment          = "${var.environment}-${var.country_code}"
  domain_name          = var.domain_name
  vpc_id               = module.vpc.vpc_id
  internal_dns_records = {}
  tags                 = local.common_tags
}

# =============================================================================
# TOGGLEABLE MODULES  –  count = local.mod.X ? 1 : 0
# =============================================================================

# -----------------------------------------------------------------------------
# ACM – created only when ALB is enabled (they are a unit)
# -----------------------------------------------------------------------------
module "acm" {
  count  = local.mod.alb ? 1 : 0
  source = "../modules/acm"

  project     = "helixbeat"
  environment = "${var.environment}-${var.country_code}"

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}", var.domain_name]
  route53_zone_id           = module.route53.public_zone_id
  tags                      = local.common_tags

  depends_on = [module.route53]
}

# -----------------------------------------------------------------------------
# ALB  (modules.alb)
# Disable for internal-only or greenfield EKS-only deployments.
# Note: ACM, Route53 alias records and health check are also skipped.
# -----------------------------------------------------------------------------
module "alb" {
  count  = local.mod.alb ? 1 : 0
  source = "../modules/alb"

  project     = "helixbeat"
  environment = "${var.environment}-${var.country_code}"

  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  public_subnet_ids = module.vpc.public_subnet_ids

  acm_certificate_arn        = one(module.acm[*].certificate_arn)
  waf_web_acl_arn            = module.security.waf_web_acl_arn
  health_check_path          = "/health"
  enable_deletion_protection = var.alb_enable_deletion_protection

  access_logs_bucket        = "${local.name_prefix}-alb-logs-${data.aws_caller_identity.current.account_id}"
  create_access_logs_bucket = true

  alarm_sns_topic_arns = [module.security.security_alerts_sns_topic_arn]
  tags                 = local.common_tags

  depends_on = [module.acm]
}

# ── Inline Route 53 alias records (only when ALB is enabled) ──────────────

resource "aws_route53_record" "apex" {
  count   = local.mod.alb ? 1 : 0
  zone_id = module.route53.public_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = local.alb_dns
    zone_id                = local.alb_zone
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wildcard" {
  count   = local.mod.alb ? 1 : 0
  zone_id = module.route53.public_zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = local.alb_dns
    zone_id                = local.alb_zone
    evaluate_target_health = true
  }
}

resource "aws_route53_health_check" "primary" {
  count             = local.mod.alb ? 1 : 0
  fqdn              = local.alb_dns
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  enable_sni        = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-hc-primary" })
}

# -----------------------------------------------------------------------------
# EKS  (modules.eks)
# Disable for EC2-only or data-tier-only deployments.
# Note: IAM IRSA roles become empty references; EFS loses the node SG.
# -----------------------------------------------------------------------------
module "eks" {
  count  = local.mod.eks ? 1 : 0
  source = "../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  system_node_instance_types = local.system_node_types
  system_node_desired        = var.system_node_desired
  system_node_min            = var.system_node_min
  system_node_max            = var.system_node_max

  app_node_instance_types = local.app_node_types
  app_node_desired        = var.app_node_desired
  app_node_min            = var.app_node_min
  app_node_max            = var.app_node_max

  ecr_repositories = var.ecr_repositories
  tags             = local.common_tags
}

# -----------------------------------------------------------------------------
# IAM / IRSA  (modules.iam)
# Disable if IAM roles are managed externally or via a separate Terraform state.
# -----------------------------------------------------------------------------
module "iam" {
  count  = local.mod.iam ? 1 : 0
  source = "../modules/iam"

  cluster_name           = local.cluster_name
  oidc_provider_arn      = local.eks_oidc_arn
  oidc_provider_url      = local.eks_oidc_url
  monitoring_bucket_name = "${local.name_prefix}-monitoring-${data.aws_caller_identity.current.account_id}"
  general_kms_key_arn    = module.security.general_kms_key_arn
  tags                   = local.common_tags
}

# -----------------------------------------------------------------------------
# EFS  (modules.efs)
# Disable if Kafka uses EBS PVCs or no shared storage is needed.
# -----------------------------------------------------------------------------
module "efs" {
  count  = local.mod.efs ? 1 : 0
  source = "../modules/efs"

  project     = "helixbeat"
  environment = "${var.environment}-${var.country_code}"

  vpc_id                      = module.vpc.vpc_id
  private_subnet_ids          = module.vpc.private_subnet_ids
  eks_node_security_group_ids = compact([local.eks_node_sg])
  kms_key_arn                 = module.security.general_kms_key_arn
  oidc_provider_arn           = local.eks_oidc_arn
  oidc_provider_url           = local.eks_oidc_url
  throughput_mode             = local.region_efs_mode
  tags                        = local.common_tags
}

# -----------------------------------------------------------------------------
# EC2  (modules.ec2)
# Disable for pure EKS / containerised workloads with no legacy VMs.
# Note: DocumentDB loses the EC2 security group from its allowed list.
# -----------------------------------------------------------------------------
module "ec2" {
  count  = local.mod.ec2 ? 1 : 0
  source = "../modules/ec2"

  project     = "helixbeat"
  environment = "${var.environment}-${var.country_code}"

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = local.alb_sg
  kms_key_arn           = module.security.general_kms_key_arn

  ami_id               = var.ec2_ami_id
  instance_type        = "${local.region_instance_family}.${split(".", var.ec2_instance_type)[1]}"
  root_volume_size_gb  = var.ec2_root_volume_size_gb
  asg_min_size         = var.asg_min_size
  asg_max_size         = var.asg_max_size
  asg_desired_capacity = var.asg_desired_capacity
  target_group_arns    = compact([local.alb_tg_arn])

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# DocumentDB  (modules.documentdb)
# Disable if using an external DB, Atlas, or a different data store.
# -----------------------------------------------------------------------------
module "documentdb" {
  count  = local.mod.documentdb ? 1 : 0
  source = "../modules/documentdb"

  project     = "helixbeat"
  environment = "${var.environment}-${var.country_code}"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # compact() removes empty strings so the SG list stays valid when
  # EKS or EC2 modules are disabled
  allowed_security_group_ids = compact([
    local.eks_node_sg,
    local.ec2_sg,
  ])

  kms_key_arn           = module.security.general_kms_key_arn
  engine_version        = "5.0.0"
  instance_class        = "${local.region_docdb_class}.${split(".", var.documentdb_instance_class)[2]}"
  instance_count        = var.documentdb_instance_count
  backup_retention_days = 35
  deletion_protection   = var.documentdb_deletion_protection

  alarm_sns_topic_arns = [module.security.security_alerts_sns_topic_arn]
  tags                 = local.common_tags
}

# ── Internal CNAME (only when DocumentDB is enabled) ──────────────────────

resource "aws_route53_record" "documentdb_internal" {
  count   = local.mod.documentdb ? 1 : 0
  zone_id = module.route53.private_zone_id
  name    = "documentdb.internal.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = [local.docdb_endpoint]
}

# -----------------------------------------------------------------------------
# S3  (modules.s3)
# Disable for minimal/ephemeral environments with no persistent object storage.
# -----------------------------------------------------------------------------
module "s3" {
  count  = local.mod.s3 ? 1 : 0
  source = "../modules/s3"

  project     = "helixbeat"
  environment = "${var.environment}-${var.country_code}"
  aws_region  = var.aws_region

  kms_key_arn = module.security.general_kms_key_arn

  # compact() handles the case when IAM or EC2 modules are disabled
  allowed_role_arns = compact([
    local.iam_monitor_arn,
    local.ec2_role_arn,
  ])

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# AWS Backup  (modules.backup)
# Disable if backup is managed by a central/shared Terraform state.
# DocumentDB and EFS selections are automatically skipped if those modules
# are also disabled.
# -----------------------------------------------------------------------------
module "backup" {
  count  = local.mod.backup ? 1 : 0
  source = "../modules/backup"

  project     = "helixbeat"
  environment = "${var.environment}-${var.country_code}"

  kms_key_arn = module.security.general_kms_key_arn

  # Build the DocumentDB ARN only when that module is enabled
  documentdb_cluster_arns = local.mod.documentdb ? [
    "arn:aws:docdb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster:${local.docdb_id}"
  ] : []

  # Pass an empty list when EFS is disabled
  efs_file_system_arns = local.mod.efs ? [local.efs_arn] : []

  alarm_sns_topic_arn = module.security.security_alerts_sns_topic_arn
  tags                = local.common_tags
}
