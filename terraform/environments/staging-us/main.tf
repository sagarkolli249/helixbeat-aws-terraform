###############################################################################
# HelixBeat – Staging / US (us-east-1)
# VPC CIDR: 10.30.0.0/16  –  production-like sizing
###############################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
  backend "s3" {
    bucket         = "helixbeat-tfstate-staging-us"
    key            = "staging-us/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "helixbeat-tfstate-lock-staging-us"
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "helixbeat"
  default_tags { tags = { ManagedBy = "terraform" } }
}

module "helixbeat" {
  source = "../../env-base"

  country_code       = "us"
  environment        = "staging"
  aws_region         = "us-east-1"
  vpc_cidr           = "10.30.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  domain_name        = "staging-us.helixbeat.com"
  kubernetes_version = "1.29"
  ec2_ami_id         = "ami-0c02fb55956c7d316" # Amazon Linux 2023 us-east-1

  alert_email_addresses = ["platform@helixbeat.com"]

  # Staging – production-like sizing
  app_node_instance_types = ["m5.xlarge"]
  app_node_desired        = 2
  app_node_min            = 2
  app_node_max            = 8
  system_node_min         = 2
  system_node_max         = 4

  ec2_instance_type       = "m5.xlarge"
  ec2_root_volume_size_gb = 100
  asg_min_size            = 2
  asg_max_size            = 8
  asg_desired_capacity    = 2

  documentdb_instance_class      = "db.r6g.xlarge"
  documentdb_deletion_protection = true
  alb_enable_deletion_protection = true

  # ── Module toggles ───────────────────────────────────────────────────────────
  # Staging deploys the full stack. Set individual flags to false only when
  # temporarily disabling a module (e.g. during a planned maintenance window).
  modules = {}
}

output "vpc_id"                    { value = module.helixbeat.vpc_id }
output "enabled_modules"           { value = module.helixbeat.enabled_modules }
output "route53_name_servers"      { value = module.helixbeat.route53_name_servers }
output "cluster_name"              { value = module.helixbeat.cluster_name }
output "kubeconfig_command"        { value = module.helixbeat.kubeconfig_command }
output "alb_dns_name"              { value = module.helixbeat.alb_dns_name }
output "documentdb_endpoint"       { value = module.helixbeat.documentdb_endpoint;       sensitive = true }
output "documentdb_secret_arn"     { value = module.helixbeat.documentdb_secret_arn }
output "s3_app_data_bucket"        { value = module.helixbeat.s3_app_data_bucket }
output "s3_backups_bucket"         { value = module.helixbeat.s3_backups_bucket }
output "monitoring_bucket_name"    { value = module.helixbeat.monitoring_bucket_name }
output "efs_file_system_id"        { value = module.helixbeat.efs_file_system_id }
output "efs_kafka_access_point_id" { value = module.helixbeat.efs_kafka_access_point_id }
output "backup_vault_name"         { value = module.helixbeat.backup_vault_name }
output "guardduty_detector_id"     { value = module.helixbeat.guardduty_detector_id }
output "general_kms_key_arn"       { value = module.helixbeat.general_kms_key_arn }
