output "file_system_id" {
  value = aws_efs_file_system.this.id
}

output "file_system_arn" {
  value = aws_efs_file_system.this.arn
}

output "kafka_access_point_id" {
  description = "EFS access point ID for Kafka on EKS"
  value       = aws_efs_access_point.kafka.id
}

output "app_access_point_id" {
  value = aws_efs_access_point.app.id
}

output "efs_csi_role_arn" {
  description = "IRSA role ARN for EFS CSI driver"
  value       = aws_iam_role.efs_csi.arn
}

output "security_group_id" {
  value = aws_security_group.efs.id
}
