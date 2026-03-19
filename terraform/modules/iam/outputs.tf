output "cluster_autoscaler_role_arn" {
  value = aws_iam_role.cluster_autoscaler.arn
}

output "aws_lb_controller_role_arn" {
  value = aws_iam_role.aws_lb_controller.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}

output "monitoring_role_arn" {
  value = aws_iam_role.monitoring.arn
}

output "monitoring_bucket_name" {
  value = aws_s3_bucket.monitoring.bucket
}

output "monitoring_bucket_arn" {
  value = aws_s3_bucket.monitoring.arn
}
