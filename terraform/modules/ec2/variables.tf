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
variable "private_subnet_ids" {
  type = list(string)
}
variable "alb_security_group_id" {
  type = string
}
variable "kms_key_arn" {
  type = string
}
variable "ami_id" {
  description = "Amazon Linux 2 or custom hardened AMI ID"
  type        = string
}
variable "instance_type" {
  type    = string
  default = "m5.large"
}
variable "root_volume_size_gb" {
  type    = number
  default = 50
}
variable "asg_min_size" {
  type    = number
  default = 1
}
variable "asg_max_size" {
  type    = number
  default = 6
}
variable "asg_desired_capacity" {
  type    = number
  default = 2
}
variable "target_group_arns" {
  description = "ALB target group ARNs"
  type        = list(string)
  default     = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
