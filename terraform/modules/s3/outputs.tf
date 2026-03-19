output "bucket_ids" {
  description = "Map of logical name → bucket ID"
  value       = { for k, v in aws_s3_bucket.this : k => v.id }
}

output "bucket_arns" {
  description = "Map of logical name → bucket ARN"
  value       = { for k, v in aws_s3_bucket.this : k => v.arn }
}

output "app_data_bucket_name" {
  value = aws_s3_bucket.this["app-data"].id
}

output "backups_bucket_name" {
  value = aws_s3_bucket.this["backups"].id
}

output "artifacts_bucket_name" {
  value = aws_s3_bucket.this["artifacts"].id
}
