###############################################################################
# HelixBeat – env-base variables
# Every country+environment deployment passes these in. Adding a new country
# is purely additive – create a new environments/{env}-{country}/ directory
# and call this module with the appropriate values.
###############################################################################

variable "country_code" {
  description = "Two-letter ISO country code used in all resource names (us, in, om, my, lk, id)"
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}$", var.country_code))
    error_message = "country_code must be exactly two lowercase letters (e.g. 'us', 'in')."
  }
}

variable "environment" {
  description = "Deployment tier: dev or staging"
  type        = string
  validation {
    condition     = contains(["dev", "staging"], var.environment)
    error_message = "environment must be 'dev' or 'staging'."
  }
}

variable "aws_region" {
  description = "AWS region for this country deployment"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (must be unique across all country/env deployments)"
  type        = string
}

variable "availability_zones" {
  description = "List of AZs within the region (typically 3)"
  type        = list(string)
}

variable "domain_name" {
  description = "Country-scoped domain (e.g. 'in.helixbeat.com', 'us.helixbeat.com')"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "alert_email_addresses" {
  description = "Email addresses for security/ops SNS alerts"
  type        = list(string)
  default     = []
}

variable "ecr_repositories" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["helixbeat-api", "helixbeat-worker", "helixbeat-frontend"]
}

variable "ec2_ami_id" {
  description = "AMI ID for EC2 instances (Amazon Linux 2023 in the target region)"
  type        = string
}

# ── Sizing (overridden per environment) ──────────────────────────────────────

variable "system_node_instance_types" {
  description = "Override system node instance types. Leave null to auto-select based on region capability map (m5 or m6i)."
  type    = list(string)
  default = null
}

variable "system_node_desired" {
  type    = number
  default = 2
}
variable "system_node_min" {
  type    = number
  default = 1
}
variable "system_node_max" {
  type    = number
  default = 3
}

variable "app_node_instance_types" {
  description = "Override app node instance types. Leave null to auto-select based on region capability map (m5 or m6i)."
  type    = list(string)
  default = null
}

variable "app_node_desired" {
  type    = number
  default = 1
}
variable "app_node_min" {
  type    = number
  default = 1
}
variable "app_node_max" {
  type    = number
  default = 5
}

variable "documentdb_instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "documentdb_instance_count" {
  type    = number
  default = 3
}

variable "documentdb_deletion_protection" {
  type    = bool
  default = false
}

variable "ec2_instance_type" {
  type    = string
  default = "m5.large"
}
variable "ec2_root_volume_size_gb" {
  type    = number
  default = 50
}
variable "asg_min_size" {
  type    = number
  default = 1
}
variable "asg_max_size" {
  type    = number
  default = 4
}
variable "asg_desired_capacity" {
  type    = number
  default = 1
}

variable "alb_enable_deletion_protection" {
  type    = bool
  default = false
}

variable "tags" {
  description = "Additional tags merged on top of the standard tag set"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Regional feature overrides
# The env-base locals{} already provide sensible per-region defaults via the
# region_config map. You only need these variables if you want to override
# the auto-detected capability for a specific deployment.
# ---------------------------------------------------------------------------

variable "efs_throughput_mode" {
  description = "EFS throughput mode. Auto-set to 'bursting' for regions where elastic throughput is not available."
  type        = string
  default     = null  # null = auto-detect from region_config
}

variable "vpc_excluded_endpoints" {
  description = "VPC interface endpoint services to exclude (for regions missing specific endpoints)."
  type        = list(string)
  default     = null  # null = auto-detect from region_config
}

variable "enable_securityhub_standards" {
  description = "Enable SecurityHub CIS/FSBP standards. Auto-set to false for regions where not available."
  type        = bool
  default     = null  # null = auto-detect from region_config
}

variable "enable_guardduty_advanced" {
  description = "Enable GuardDuty Kubernetes + malware protection. Auto-set to false for regions where not available."
  type        = bool
  default     = null  # null = auto-detect from region_config
}

# ---------------------------------------------------------------------------
# Module enable / disable flags
#
# Use this single object to turn modules on or off for a specific deployment.
# Every flag defaults to true (full stack). Set individual flags to false to
# exclude a module — useful for cost optimisation, phased rollouts, or
# environments where a service is managed outside Terraform.
#
# Dependency rules (Terraform does NOT enforce these — you must respect them):
#   alb=false  → acm is also skipped; inline Route53 alias records are skipped
#   eks=false  → iam / efs will deploy without IRSA (OIDC refs become "")
#   ec2=false  → documentdb allowed_security_group_ids loses the EC2 SG
#   iam=false  → s3 monitoring role reference becomes ""; EKS controllers lose IRSA
#   efs=false  → Kafka must use EBS PVCs instead; backup skips EFS selection
#   documentdb=false → backup skips DocumentDB; internal CNAME record is skipped
#
# Example – EKS-only, no EC2, no Backup:
#   modules = { ec2 = false, backup = false }
#
# Example – Data-plane only (no public ALB, no EKS):
#   modules = { alb = false, eks = false, iam = false }
# ---------------------------------------------------------------------------
variable "modules" {
  description = "Fine-grained enable/disable flags for each infrastructure module."
  type = object({
    alb        = optional(bool, true)   # Internet-facing ALB + ACM certificate
    eks        = optional(bool, true)   # EKS cluster, node groups, ECR
    ec2        = optional(bool, true)   # EC2 ASG for legacy VMs (IMDSv2, SSM, Inspector)
    iam        = optional(bool, true)   # IRSA roles (autoscaler, ALB controller, Prometheus)
    documentdb = optional(bool, true)   # DocumentDB cluster (MongoDB 5.0 API)
    s3         = optional(bool, true)   # S3 app-data / backups / artifacts buckets
    efs        = optional(bool, true)   # EFS shared storage (Kafka + app access points)
    backup     = optional(bool, true)   # AWS Backup vault with Vault Lock
  })
  default = {}   # all modules enabled by default
}
