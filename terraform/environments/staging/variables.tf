variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "ecr_repositories" {
  type    = list(string)
  default = ["api", "worker", "frontend"]
}

variable "alert_email_addresses" {
  type    = list(string)
  default = []
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "helixbeat.com"
}

variable "ec2_ami_id" {
  description = "Amazon Linux 2 AMI ID"
  type        = string
  default     = "ami-0c02fb55956c7d316"
}
