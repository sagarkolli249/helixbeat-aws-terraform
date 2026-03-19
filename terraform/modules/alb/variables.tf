variable "project" {
  type    = string
  default = "helixbeat"
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  description = "VPC CIDR – used for ALB→node egress rule"
  type        = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener"
  type        = string
}

variable "waf_web_acl_arn" {
  description = "WAFv2 Web ACL ARN from security module"
  type        = string
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "enable_deletion_protection" {
  type    = bool
  default = true
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  type        = string
}

variable "create_access_logs_bucket" {
  description = "Create the access logs bucket (false if it already exists)"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arns" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
