variable "project" { type = string; default = "helixbeat" }
variable "environment" { type = string }
variable "kms_key_arn" { type = string }
variable "documentdb_cluster_arns" { type = list(string); default = [] }
variable "efs_file_system_arns" { type = list(string); default = [] }
variable "alarm_sns_topic_arn" { type = string; default = "" }
variable "tags" { type = map(string); default = {} }
