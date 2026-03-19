<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_acm"></a> [acm](#module\_acm) | ../modules/acm | n/a |
| <a name="module_alb"></a> [alb](#module\_alb) | ../modules/alb | n/a |
| <a name="module_backup"></a> [backup](#module\_backup) | ../modules/backup | n/a |
| <a name="module_documentdb"></a> [documentdb](#module\_documentdb) | ../modules/documentdb | n/a |
| <a name="module_ec2"></a> [ec2](#module\_ec2) | ../modules/ec2 | n/a |
| <a name="module_efs"></a> [efs](#module\_efs) | ../modules/efs | n/a |
| <a name="module_eks"></a> [eks](#module\_eks) | ../modules/eks | n/a |
| <a name="module_iam"></a> [iam](#module\_iam) | ../modules/iam | n/a |
| <a name="module_route53"></a> [route53](#module\_route53) | ../modules/route53 | n/a |
| <a name="module_s3"></a> [s3](#module\_s3) | ../modules/s3 | n/a |
| <a name="module_security"></a> [security](#module\_security) | ../modules/security | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ../modules/vpc | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_route53_health_check.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_health_check) | resource |
| [aws_route53_record.apex](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.documentdb_internal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.wildcard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_enable_deletion_protection"></a> [alb\_enable\_deletion\_protection](#input\_alb\_enable\_deletion\_protection) | n/a | `bool` | `false` | no |
| <a name="input_alert_email_addresses"></a> [alert\_email\_addresses](#input\_alert\_email\_addresses) | Email addresses for security/ops SNS alerts | `list(string)` | `[]` | no |
| <a name="input_app_node_desired"></a> [app\_node\_desired](#input\_app\_node\_desired) | n/a | `number` | `1` | no |
| <a name="input_app_node_instance_types"></a> [app\_node\_instance\_types](#input\_app\_node\_instance\_types) | Override app node instance types. Leave null to auto-select based on region capability map (m5 or m6i). | `list(string)` | `null` | no |
| <a name="input_app_node_max"></a> [app\_node\_max](#input\_app\_node\_max) | n/a | `number` | `5` | no |
| <a name="input_app_node_min"></a> [app\_node\_min](#input\_app\_node\_min) | n/a | `number` | `1` | no |
| <a name="input_asg_desired_capacity"></a> [asg\_desired\_capacity](#input\_asg\_desired\_capacity) | n/a | `number` | `1` | no |
| <a name="input_asg_max_size"></a> [asg\_max\_size](#input\_asg\_max\_size) | n/a | `number` | `4` | no |
| <a name="input_asg_min_size"></a> [asg\_min\_size](#input\_asg\_min\_size) | n/a | `number` | `1` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | List of AZs within the region (typically 3) | `list(string)` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for this country deployment | `string` | n/a | yes |
| <a name="input_country_code"></a> [country\_code](#input\_country\_code) | Two-letter ISO country code used in all resource names (us, in, om, my, lk, id) | `string` | n/a | yes |
| <a name="input_documentdb_deletion_protection"></a> [documentdb\_deletion\_protection](#input\_documentdb\_deletion\_protection) | n/a | `bool` | `false` | no |
| <a name="input_documentdb_instance_class"></a> [documentdb\_instance\_class](#input\_documentdb\_instance\_class) | n/a | `string` | `"db.r6g.large"` | no |
| <a name="input_documentdb_instance_count"></a> [documentdb\_instance\_count](#input\_documentdb\_instance\_count) | n/a | `number` | `3` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Country-scoped domain (e.g. 'in.helixbeat.com', 'us.helixbeat.com') | `string` | n/a | yes |
| <a name="input_ec2_ami_id"></a> [ec2\_ami\_id](#input\_ec2\_ami\_id) | AMI ID for EC2 instances (Amazon Linux 2023 in the target region) | `string` | n/a | yes |
| <a name="input_ec2_instance_type"></a> [ec2\_instance\_type](#input\_ec2\_instance\_type) | n/a | `string` | `"m5.large"` | no |
| <a name="input_ec2_root_volume_size_gb"></a> [ec2\_root\_volume\_size\_gb](#input\_ec2\_root\_volume\_size\_gb) | n/a | `number` | `50` | no |
| <a name="input_ecr_repositories"></a> [ecr\_repositories](#input\_ecr\_repositories) | List of ECR repository names to create | `list(string)` | <pre>[<br>  "helixbeat-api",<br>  "helixbeat-worker",<br>  "helixbeat-frontend"<br>]</pre> | no |
| <a name="input_efs_throughput_mode"></a> [efs\_throughput\_mode](#input\_efs\_throughput\_mode) | EFS throughput mode. Auto-set to 'bursting' for regions where elastic throughput is not available. | `string` | `null` | no |
| <a name="input_enable_guardduty_advanced"></a> [enable\_guardduty\_advanced](#input\_enable\_guardduty\_advanced) | Enable GuardDuty Kubernetes + malware protection. Auto-set to false for regions where not available. | `bool` | `null` | no |
| <a name="input_enable_securityhub_standards"></a> [enable\_securityhub\_standards](#input\_enable\_securityhub\_standards) | Enable SecurityHub CIS/FSBP standards. Auto-set to false for regions where not available. | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment tier: dev or staging | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | EKS Kubernetes version | `string` | `"1.29"` | no |
| <a name="input_modules"></a> [modules](#input\_modules) | Fine-grained enable/disable flags for each infrastructure module. | <pre>object({<br>    alb        = optional(bool, true) # Internet-facing ALB + ACM certificate<br>    eks        = optional(bool, true) # EKS cluster, node groups, ECR<br>    ec2        = optional(bool, true) # EC2 ASG for legacy VMs (IMDSv2, SSM, Inspector)<br>    iam        = optional(bool, true) # IRSA roles (autoscaler, ALB controller, Prometheus)<br>    documentdb = optional(bool, true) # DocumentDB cluster (MongoDB 5.0 API)<br>    s3         = optional(bool, true) # S3 app-data / backups / artifacts buckets<br>    efs        = optional(bool, true) # EFS shared storage (Kafka + app access points)<br>    backup     = optional(bool, true) # AWS Backup vault with Vault Lock<br>  })</pre> | `{}` | no |
| <a name="input_system_node_desired"></a> [system\_node\_desired](#input\_system\_node\_desired) | n/a | `number` | `2` | no |
| <a name="input_system_node_instance_types"></a> [system\_node\_instance\_types](#input\_system\_node\_instance\_types) | Override system node instance types. Leave null to auto-select based on region capability map (m5 or m6i). | `list(string)` | `null` | no |
| <a name="input_system_node_max"></a> [system\_node\_max](#input\_system\_node\_max) | n/a | `number` | `3` | no |
| <a name="input_system_node_min"></a> [system\_node\_min](#input\_system\_node\_min) | n/a | `number` | `1` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged on top of the standard tag set | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR block (must be unique across all country/env deployments) | `string` | n/a | yes |
| <a name="input_vpc_excluded_endpoints"></a> [vpc\_excluded\_endpoints](#input\_vpc\_excluded\_endpoints) | VPC interface endpoint services to exclude (for regions missing specific endpoints). | `list(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_acm_certificate_arn"></a> [acm\_certificate\_arn](#output\_acm\_certificate\_arn) | ACM wildcard certificate ARN (null when alb module disabled) |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | ALB DNS name for CNAME / alias records (null when alb module disabled) |
| <a name="output_alb_zone_id"></a> [alb\_zone\_id](#output\_alb\_zone\_id) | ALB hosted zone ID (null when alb module disabled) |
| <a name="output_backup_vault_name"></a> [backup\_vault\_name](#output\_backup\_vault\_name) | AWS Backup vault name (null when backup disabled) |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | EKS API server endpoint (null when eks module disabled) |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | EKS cluster name (null when eks module disabled) |
| <a name="output_documentdb_cluster_id"></a> [documentdb\_cluster\_id](#output\_documentdb\_cluster\_id) | DocumentDB cluster resource ID (null when documentdb disabled) |
| <a name="output_documentdb_endpoint"></a> [documentdb\_endpoint](#output\_documentdb\_endpoint) | DocumentDB primary endpoint (null when documentdb disabled) |
| <a name="output_documentdb_reader_endpoint"></a> [documentdb\_reader\_endpoint](#output\_documentdb\_reader\_endpoint) | DocumentDB reader endpoint (null when documentdb disabled) |
| <a name="output_documentdb_secret_arn"></a> [documentdb\_secret\_arn](#output\_documentdb\_secret\_arn) | Secrets Manager ARN holding DocumentDB credentials (null when disabled) |
| <a name="output_ec2_asg_name"></a> [ec2\_asg\_name](#output\_ec2\_asg\_name) | Auto Scaling Group name for migrated EC2 workloads (null when ec2 disabled) |
| <a name="output_ec2_instance_role_arn"></a> [ec2\_instance\_role\_arn](#output\_ec2\_instance\_role\_arn) | IAM instance role ARN for EC2 nodes (null when ec2 disabled) |
| <a name="output_ec2_security_group_id"></a> [ec2\_security\_group\_id](#output\_ec2\_security\_group\_id) | EC2 instance security group ID (null when ec2 disabled) |
| <a name="output_ecr_repository_urls"></a> [ecr\_repository\_urls](#output\_ecr\_repository\_urls) | Map of ECR repository name → URL (empty when eks module disabled) |
| <a name="output_efs_file_system_arn"></a> [efs\_file\_system\_arn](#output\_efs\_file\_system\_arn) | EFS file system ARN (null when efs disabled) |
| <a name="output_efs_file_system_id"></a> [efs\_file\_system\_id](#output\_efs\_file\_system\_id) | EFS file system ID (null when efs disabled) |
| <a name="output_efs_kafka_access_point_id"></a> [efs\_kafka\_access\_point\_id](#output\_efs\_kafka\_access\_point\_id) | EFS access point ID used by Strimzi Kafka brokers (null when efs disabled) |
| <a name="output_enabled_modules"></a> [enabled\_modules](#output\_enabled\_modules) | Map showing which optional modules were deployed in this environment |
| <a name="output_general_kms_key_arn"></a> [general\_kms\_key\_arn](#output\_general\_kms\_key\_arn) | KMS key ARN used for envelope encryption across all resources |
| <a name="output_guardduty_detector_id"></a> [guardduty\_detector\_id](#output\_guardduty\_detector\_id) | GuardDuty detector ID for this account/region |
| <a name="output_health_check_id"></a> [health\_check\_id](#output\_health\_check\_id) | Route 53 health check ID for the primary ALB (null when alb module disabled) |
| <a name="output_kubeconfig_command"></a> [kubeconfig\_command](#output\_kubeconfig\_command) | aws eks update-kubeconfig command for this cluster |
| <a name="output_monitoring_bucket_name"></a> [monitoring\_bucket\_name](#output\_monitoring\_bucket\_name) | S3 bucket name used by the monitoring stack (null when iam disabled) |
| <a name="output_monitoring_role_arn"></a> [monitoring\_role\_arn](#output\_monitoring\_role\_arn) | IRSA role ARN for the monitoring/Prometheus stack (null when iam disabled) |
| <a name="output_node_security_group_id"></a> [node\_security\_group\_id](#output\_node\_security\_group\_id) | EKS managed node group security group ID (null when eks disabled) |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | List of private subnet IDs (EKS nodes / EC2 / data tier) |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | List of public subnet IDs (ALB / NAT) |
| <a name="output_route53_name_servers"></a> [route53\_name\_servers](#output\_route53\_name\_servers) | Delegate these NS records at your registrar for this country domain |
| <a name="output_route53_private_zone_id"></a> [route53\_private\_zone\_id](#output\_route53\_private\_zone\_id) | Private hosted zone ID (internal service discovery) |
| <a name="output_route53_public_zone_id"></a> [route53\_public\_zone\_id](#output\_route53\_public\_zone\_id) | Public hosted zone ID |
| <a name="output_s3_app_data_bucket"></a> [s3\_app\_data\_bucket](#output\_s3\_app\_data\_bucket) | S3 app-data bucket name (null when s3 disabled) |
| <a name="output_s3_artifacts_bucket"></a> [s3\_artifacts\_bucket](#output\_s3\_artifacts\_bucket) | S3 artifacts bucket name (null when s3 disabled) |
| <a name="output_s3_backups_bucket"></a> [s3\_backups\_bucket](#output\_s3\_backups\_bucket) | S3 backups bucket name (null when s3 disabled) |
| <a name="output_security_alerts_sns_topic_arn"></a> [security\_alerts\_sns\_topic\_arn](#output\_security\_alerts\_sns\_topic\_arn) | SNS topic ARN for security and operational alerts |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | VPC CIDR block |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the VPC |
| <a name="output_waf_web_acl_arn"></a> [waf\_web\_acl\_arn](#output\_waf\_web\_acl\_arn) | WAFv2 Web ACL ARN (attached to ALB) |
<!-- END_TF_DOCS -->