variable "project" {
  description = "Project name prefix used in resource naming"
  type        = string
  default     = "helixbeat"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to deploy subnets into (must have at least 2)"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name (used for subnet tagging)"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "interface_endpoints" {
  description = <<-EOT
    List of AWS service names to create Interface VPC Endpoints for.
    Override per country to drop services not yet available in a region.
    Full list available: https://docs.aws.amazon.com/vpc/latest/privatelink/aws-services-privatelink-support.html
  EOT
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "ec2",
    "sts",
    "logs",
    "ssm",
    "ssmmessages",
    "ec2messages",
    "elasticloadbalancing",
    "autoscaling",
  ]
}

variable "excluded_endpoints" {
  description = <<-EOT
    Services to remove from interface_endpoints. Use this for regions where
    specific VPC endpoint services are not yet available (e.g. ap-southeast-5,
    me-central-1 may be missing elasticloadbalancing or autoscaling).
  EOT
  type        = list(string)
  default     = []
}
