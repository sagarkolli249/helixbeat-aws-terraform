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
variable "eks_node_security_group_ids" {
  type = list(string)
}
variable "kms_key_arn" {
  type = string
}
variable "oidc_provider_arn" {
  type = string
}
variable "oidc_provider_url" {
  type = string
}
variable "performance_mode" {
  type    = string
  default = "generalPurpose"
}
variable "throughput_mode" {
  type    = string
  default = "elastic"
}
variable "tags" {
  type    = map(string)
  default = {}
}
