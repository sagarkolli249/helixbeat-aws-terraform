output "vpc_id" {
  value = module.vpc.vpc_id
}
output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}
output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}
output "route53_name_servers" {
  value = module.route53.public_zone_name_servers
}
output "acm_certificate_arn" {
  value = module.acm.certificate_arn
}
output "alb_dns_name" {
  value = module.alb.alb_dns_name
}
output "cluster_name" {
  value = module.eks.cluster_name
}
output "cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}
output "ecr_repository_urls" {
  value = module.eks.ecr_repository_urls
}
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
output "monitoring_role_arn" {
  value = module.iam.monitoring_role_arn
}
output "monitoring_bucket_name" {
  value = module.iam.monitoring_bucket_name
}
output "documentdb_endpoint" {
  value     = module.documentdb.cluster_endpoint
  sensitive = true
}
output "documentdb_reader_endpoint" {
  value     = module.documentdb.cluster_reader_endpoint
  sensitive = true
}
output "documentdb_secret_arn" {
  value = module.documentdb.credentials_secret_arn
}
output "s3_app_data_bucket" {
  value = module.s3.app_data_bucket_name
}
output "s3_backups_bucket" {
  value = module.s3.backups_bucket_name
}
output "efs_file_system_id" {
  value = module.efs.file_system_id
}
output "efs_kafka_access_point_id" {
  value = module.efs.kafka_access_point_id
}
output "waf_web_acl_arn" {
  value = module.security.waf_web_acl_arn
}
output "guardduty_detector_id" {
  value = module.security.guardduty_detector_id
}
output "backup_vault_name" {
  value = module.backup.vault_name
}
output "ec2_asg_name" {
  value = module.ec2.asg_name
}
output "ec2_security_group_id" {
  value = module.ec2.security_group_id
}
output "health_check_id" {
  value = aws_route53_health_check.primary.id
}
