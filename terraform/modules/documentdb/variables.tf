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

variable "subnet_ids" {
  description = "Data tier private subnet IDs"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect on port 27017 (EKS nodes, EC2)"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption at rest"
  type        = string
}

variable "engine_version" {
  description = "DocumentDB engine version"
  type        = string
  default     = "5.0.0"
}

variable "instance_class" {
  description = "DocumentDB instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Number of instances (one per AZ for HA)"
  type        = number
  default     = 3
}

variable "master_username" {
  description = "Master DB username"
  type        = string
  default     = "helixadmin"
}

variable "database_name" {
  description = "Initial database name"
  type        = string
  default     = "helixbeat"
}

variable "backup_retention_days" {
  description = "Automated backup retention in days (35 = maximum)"
  type        = number
  default     = 35
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "enable_performance_insights" {
  type    = bool
  default = true
}

variable "alarm_sns_topic_arns" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
