variable "project" {
  type    = string
  default = "helixbeat"
}

variable "environment" {
  type = string
}

variable "domain_name" {
  description = "Root domain name (e.g. 'helixbeat.com')"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for private hosted zone association"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name for alias records. Leave empty to skip alias/health-check resource creation (breaks circular dep)."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "ALB hosted zone ID for alias records. Leave empty to skip alias resource creation."
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "HTTP path for Route 53 health checks"
  type        = string
  default     = "/health"
}

variable "internal_dns_records" {
  description = "Map of service name → CNAME target for private zone (e.g. { 'documentdb' = 'cluster.endpoint' })"
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
