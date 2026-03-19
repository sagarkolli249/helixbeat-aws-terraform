variable "project" {
  type    = string
  default = "helixbeat"
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for SSE-KMS encryption"
  type        = string
}

variable "allowed_role_arns" {
  description = "IAM role ARNs allowed to read/write buckets (EKS IRSA roles, EC2 instance role)"
  type        = list(string)
  default     = []
}

variable "s3_vpc_endpoint_id" {
  description = "S3 Gateway VPC Endpoint ID to restrict bucket access (from vpc module output)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
