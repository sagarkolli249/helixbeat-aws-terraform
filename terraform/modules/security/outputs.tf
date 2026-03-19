output "general_kms_key_arn" {
  description = "General purpose KMS key ARN"
  value       = aws_kms_key.general.arn
}

output "general_kms_key_id" {
  description = "General purpose KMS key ID"
  value       = aws_kms_key.general.key_id
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.this.id
}

output "waf_web_acl_arn" {
  description = "WAFv2 Web ACL ARN (associate with your ALB)"
  value       = aws_wafv2_web_acl.this.arn
}

output "waf_web_acl_id" {
  description = "WAFv2 Web ACL ID"
  value       = aws_wafv2_web_acl.this.id
}

output "cloudtrail_bucket_name" {
  description = "S3 bucket for CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "config_bucket_name" {
  description = "S3 bucket for AWS Config snapshots"
  value       = aws_s3_bucket.config.bucket
}

output "security_alerts_sns_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}
