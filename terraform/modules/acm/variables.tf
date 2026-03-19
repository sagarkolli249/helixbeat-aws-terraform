variable "project" {
  type    = string
  default = "helixbeat"
}

variable "environment" {
  type = string
}

variable "domain_name" {
  description = "Primary domain (e.g. '*.helixbeat.com')"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional SANs (e.g. ['helixbeat.com'])"
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Route 53 Hosted Zone ID for DNS validation"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
