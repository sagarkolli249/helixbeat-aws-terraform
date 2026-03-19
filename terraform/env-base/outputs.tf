###############################################################################
# HelixBeat – env-base outputs
#
# All toggleable module outputs use the safe-reference pattern:
#   try(one(module.X[*].output_name), <fallback>)
# so that `terraform output` never errors when a module is disabled.
# Always-on modules (vpc, security, route53) reference outputs directly.
###############################################################################

# ── Network (always on) ───────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (ALB / NAT)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (EKS nodes / EC2 / data tier)"
  value       = module.vpc.private_subnet_ids
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

# ── DNS / TLS (route53 always on; acm/alb toggleable) ────────────────────────
output "route53_name_servers" {
  description = "Delegate these NS records at your registrar for this country domain"
  value       = module.route53.public_zone_name_servers
}

output "route53_public_zone_id" {
  description = "Public hosted zone ID"
  value       = module.route53.public_zone_id
}

output "route53_private_zone_id" {
  description = "Private hosted zone ID (internal service discovery)"
  value       = module.route53.private_zone_id
}

output "acm_certificate_arn" {
  description = "ACM wildcard certificate ARN (null when alb module disabled)"
  value       = try(one(module.acm[*].certificate_arn), null)
}

output "alb_dns_name" {
  description = "ALB DNS name for CNAME / alias records (null when alb module disabled)"
  value       = try(one(module.alb[*].alb_dns_name), null)
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (null when alb module disabled)"
  value       = try(one(module.alb[*].alb_zone_id), null)
}

output "health_check_id" {
  description = "Route 53 health check ID for the primary ALB (null when alb module disabled)"
  value       = length(aws_route53_health_check.primary) > 0 ? aws_route53_health_check.primary[0].id : null
}

# ── EKS (toggleable) ──────────────────────────────────────────────────────────
output "cluster_name" {
  description = "EKS cluster name (null when eks module disabled)"
  value       = try(one(module.eks[*].cluster_name), null)
}

output "cluster_endpoint" {
  description = "EKS API server endpoint (null when eks module disabled)"
  value       = try(one(module.eks[*].cluster_endpoint), null)
  sensitive   = true
}

output "ecr_repository_urls" {
  description = "Map of ECR repository name → URL (empty when eks module disabled)"
  value       = try(one(module.eks[*].ecr_repository_urls), {})
}

output "kubeconfig_command" {
  description = "aws eks update-kubeconfig command for this cluster"
  value = try(
    "aws eks update-kubeconfig --name ${one(module.eks[*].cluster_name)} --region ${var.aws_region} --profile helixbeat",
    "# EKS module disabled – no cluster available"
  )
}

output "node_security_group_id" {
  description = "EKS managed node group security group ID (null when eks disabled)"
  value       = try(one(module.eks[*].node_security_group_id), null)
}

# ── IAM / IRSA (toggleable) ───────────────────────────────────────────────────
output "monitoring_role_arn" {
  description = "IRSA role ARN for the monitoring/Prometheus stack (null when iam disabled)"
  value       = try(one(module.iam[*].monitoring_role_arn), null)
}

output "monitoring_bucket_name" {
  description = "S3 bucket name used by the monitoring stack (null when iam disabled)"
  value       = try(one(module.iam[*].monitoring_bucket_name), null)
}

# ── EC2 (toggleable) ──────────────────────────────────────────────────────────
output "ec2_asg_name" {
  description = "Auto Scaling Group name for migrated EC2 workloads (null when ec2 disabled)"
  value       = try(one(module.ec2[*].asg_name), null)
}

output "ec2_security_group_id" {
  description = "EC2 instance security group ID (null when ec2 disabled)"
  value       = try(one(module.ec2[*].security_group_id), null)
}

output "ec2_instance_role_arn" {
  description = "IAM instance role ARN for EC2 nodes (null when ec2 disabled)"
  value       = try(one(module.ec2[*].instance_role_arn), null)
}

# ── DocumentDB (toggleable) ───────────────────────────────────────────────────
output "documentdb_endpoint" {
  description = "DocumentDB primary endpoint (null when documentdb disabled)"
  value       = try(one(module.documentdb[*].cluster_endpoint), null)
  sensitive   = true
}

output "documentdb_reader_endpoint" {
  description = "DocumentDB reader endpoint (null when documentdb disabled)"
  value       = try(one(module.documentdb[*].cluster_reader_endpoint), null)
  sensitive   = true
}

output "documentdb_secret_arn" {
  description = "Secrets Manager ARN holding DocumentDB credentials (null when disabled)"
  value       = try(one(module.documentdb[*].credentials_secret_arn), null)
}

output "documentdb_cluster_id" {
  description = "DocumentDB cluster resource ID (null when documentdb disabled)"
  value       = try(one(module.documentdb[*].cluster_id), null)
}

# ── S3 (toggleable) ───────────────────────────────────────────────────────────
output "s3_app_data_bucket" {
  description = "S3 app-data bucket name (null when s3 disabled)"
  value       = try(one(module.s3[*].app_data_bucket_name), null)
}

output "s3_backups_bucket" {
  description = "S3 backups bucket name (null when s3 disabled)"
  value       = try(one(module.s3[*].backups_bucket_name), null)
}

output "s3_artifacts_bucket" {
  description = "S3 artifacts bucket name (null when s3 disabled)"
  value       = try(one(module.s3[*].artifacts_bucket_name), null)
}

# ── EFS (toggleable) ──────────────────────────────────────────────────────────
output "efs_file_system_id" {
  description = "EFS file system ID (null when efs disabled)"
  value       = try(one(module.efs[*].file_system_id), null)
}

output "efs_file_system_arn" {
  description = "EFS file system ARN (null when efs disabled)"
  value       = try(one(module.efs[*].file_system_arn), null)
}

output "efs_kafka_access_point_id" {
  description = "EFS access point ID used by Strimzi Kafka brokers (null when efs disabled)"
  value       = try(one(module.efs[*].kafka_access_point_id), null)
}

# ── Security (always on) ──────────────────────────────────────────────────────
output "waf_web_acl_arn" {
  description = "WAFv2 Web ACL ARN (attached to ALB)"
  value       = module.security.waf_web_acl_arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID for this account/region"
  value       = module.security.guardduty_detector_id
}

output "general_kms_key_arn" {
  description = "KMS key ARN used for envelope encryption across all resources"
  value       = module.security.general_kms_key_arn
}

output "security_alerts_sns_topic_arn" {
  description = "SNS topic ARN for security and operational alerts"
  value       = module.security.security_alerts_sns_topic_arn
}

# ── Backup (toggleable) ───────────────────────────────────────────────────────
output "backup_vault_name" {
  description = "AWS Backup vault name (null when backup disabled)"
  value       = try(one(module.backup[*].vault_name), null)
}

# ── Convenience summary ───────────────────────────────────────────────────────
output "enabled_modules" {
  description = "Map showing which optional modules were deployed in this environment"
  value = {
    alb        = var.modules.alb
    eks        = var.modules.eks
    iam        = var.modules.iam
    ec2        = var.modules.ec2
    documentdb = var.modules.documentdb
    s3         = var.modules.s3
    efs        = var.modules.efs
    backup     = var.modules.backup
  }
}
