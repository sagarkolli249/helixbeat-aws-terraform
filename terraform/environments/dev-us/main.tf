###############################################################################
# HelixBeat – Dev / US (us-east-1)
# VPC CIDR: 10.10.0.0/16
###############################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
  backend "s3" {
    bucket         = "helixbeat-tfstate-dev-us"
    key            = "dev-us/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "helixbeat-tfstate-lock-dev-us"
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags { tags = { ManagedBy = "terraform" } }
}

module "helixbeat" {
  source = "../../env-base"

  country_code       = "us"
  environment        = "dev"
  aws_region         = "us-east-1"
  vpc_cidr           = "10.10.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b"]
  single_nat_gateway  = true   # 1 NAT GW saves ~$65/mo in dev
  domain_name        = "us.helixbeat.com"
  kubernetes_version = "1.29"
  ec2_ami_id         = "ami-0c02fb55956c7d316" # Amazon Linux 2023 us-east-1

  alert_email_addresses = ["platform@helixbeat.com"]

  # Dev sizing – lean
  app_node_desired     = 1
  app_node_min         = 1
  app_node_max         = 5
  asg_desired_capacity = 1

  documentdb_deletion_protection = false
  alb_enable_deletion_protection = false

  # ── Module toggles ───────────────────────────────────────────────────────────
  # All modules default to enabled (true). Set any to false to skip deployment.
  # Omit the `modules` block entirely to deploy everything (default behaviour).
  #
  # Common patterns:
  #
  # Full stack (default – no modules block needed):
  #   modules = {}
  #
  # EKS-only (no legacy EC2 workloads):
  #   modules = { ec2 = false }
  #
  # Network + security skeleton only (no data or compute):
  #   modules = { alb = false, eks = false, iam = false, ec2 = false,
  #               documentdb = false, s3 = false, efs = false, backup = false }
  #
  # Disable backup temporarily (e.g., during initial bringup):
  #   modules = { backup = false }
  #
  # ACM and ALB disabled: us.helixbeat.com is not yet delegated at the registrar.
  # Re-enable once GoDaddy NS records point to the Route53 hosted zone.
  modules = {
    acm = false
    alb = false
  }
}

# ── Pass-through outputs ──────────────────────────────────────────────────────
output "vpc_id" { value = module.helixbeat.vpc_id }
output "enabled_modules" { value = module.helixbeat.enabled_modules }
output "route53_name_servers" { value = module.helixbeat.route53_name_servers }
output "cluster_name" { value = module.helixbeat.cluster_name }
output "kubeconfig_command" { value = module.helixbeat.kubeconfig_command }
output "alb_dns_name" { value = module.helixbeat.alb_dns_name }
output "documentdb_endpoint" {
  value     = module.helixbeat.documentdb_endpoint
  sensitive = true
}
output "documentdb_secret_arn" { value = module.helixbeat.documentdb_secret_arn }
output "s3_app_data_bucket" { value = module.helixbeat.s3_app_data_bucket }
output "s3_backups_bucket" { value = module.helixbeat.s3_backups_bucket }
output "monitoring_bucket_name" { value = module.helixbeat.monitoring_bucket_name }
output "efs_file_system_id" { value = module.helixbeat.efs_file_system_id }
output "efs_kafka_access_point_id" { value = module.helixbeat.efs_kafka_access_point_id }
output "backup_vault_name" { value = module.helixbeat.backup_vault_name }
output "guardduty_detector_id" { value = module.helixbeat.guardduty_detector_id }
output "general_kms_key_arn" { value = module.helixbeat.general_kms_key_arn }
