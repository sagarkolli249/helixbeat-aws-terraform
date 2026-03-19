variable "environment" {
  type = string
}

variable "alert_email_addresses" {
  description = "Email addresses to receive security alerts"
  type        = list(string)
  default     = []
}

variable "alarm_sns_topic_arns" {
  description = "SNS topic ARNs for CloudWatch alarms (if pre-existing; otherwise the module creates its own)"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ---------------------------------------------------------------------------
# Regional feature flags
# Set to false for regions where a service / feature is not yet available.
# ---------------------------------------------------------------------------

variable "enable_securityhub_cis_standard" {
  description = "Enable CIS AWS Foundations Benchmark standard in SecurityHub. Not available in all regions (e.g. ap-southeast-5, me-central-1)."
  type        = bool
  default     = true
}

variable "enable_securityhub_fsbp_standard" {
  description = "Enable AWS Foundational Security Best Practices standard in SecurityHub. Not available in all regions."
  type        = bool
  default     = true
}

variable "enable_guardduty_kubernetes" {
  description = "Enable GuardDuty Kubernetes audit log monitoring. Not available in all regions."
  type        = bool
  default     = true
}

variable "enable_guardduty_malware_protection" {
  description = "Enable GuardDuty malware protection for EBS volumes. Not available in all regions (newer feature)."
  type        = bool
  default     = true
}
