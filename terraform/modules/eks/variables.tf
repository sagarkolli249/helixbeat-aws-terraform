variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "VPC ID where the cluster is deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes"
  type        = list(string)
}

variable "system_node_instance_types" {
  description = "EC2 instance types for system node group"
  type        = list(string)
  default     = ["m5.large"]
}

variable "system_node_desired" {
  type    = number
  default = 2
}

variable "system_node_min" {
  type    = number
  default = 2
}

variable "system_node_max" {
  type    = number
  default = 4
}

variable "app_node_instance_types" {
  description = "EC2 instance types for application node group"
  type        = list(string)
  default     = ["m5.xlarge"]
}

variable "app_node_desired" {
  type    = number
  default = 2
}

variable "app_node_min" {
  type    = number
  default = 1
}

variable "app_node_max" {
  type    = number
  default = 10
}

variable "ecr_repositories" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["api", "worker", "frontend"]
}

variable "region_label" {
  description = "Human-readable region label applied to node group labels ('india' or 'us'). Default is 'india' — helm charts use nodeSelector region=india so workloads land on India nodes by default. Set to 'us' explicitly for US region clusters."
  type        = string
  default     = "india"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
