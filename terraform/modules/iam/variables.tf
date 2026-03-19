variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (including https://)"
  type        = string
}

variable "monitoring_bucket_name" {
  description = "S3 bucket name for monitoring long-term storage (Loki / Thanos)"
  type        = string
}

variable "general_kms_key_arn" {
  description = "General KMS key ARN from security module"
  type        = string
}

# Map of IRSA service accounts to create assume-role policies for.
# Key = logical name, value = { namespace, service_account }
variable "irsa_service_accounts" {
  description = "Service accounts that need IRSA assume-role policies"
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default = {
    "cluster-autoscaler" = {
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
    }
    "aws-lb-controller" = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    "external-dns" = {
      namespace       = "kube-system"
      service_account = "external-dns"
    }
    "monitoring" = {
      namespace       = "monitoring"
      service_account = "prometheus"
    }
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
