<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_route53_health_check.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_health_check) | resource |
| [aws_route53_record.apex](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.internal_services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.wildcard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_route53_zone.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_dns_name"></a> [alb\_dns\_name](#input\_alb\_dns\_name) | ALB DNS name for alias records. Leave empty to skip alias/health-check resource creation (breaks circular dep). | `string` | `""` | no |
| <a name="input_alb_zone_id"></a> [alb\_zone\_id](#input\_alb\_zone\_id) | ALB hosted zone ID for alias records. Leave empty to skip alias resource creation. | `string` | `""` | no |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Root domain name (e.g. 'helixbeat.com') | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | n/a | `string` | n/a | yes |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | HTTP path for Route 53 health checks | `string` | `"/health"` | no |
| <a name="input_internal_dns_records"></a> [internal\_dns\_records](#input\_internal\_dns\_records) | Map of service name → CNAME target for private zone (e.g. { 'documentdb' = 'cluster.endpoint' }) | `map(string)` | `{}` | no |
| <a name="input_project"></a> [project](#input\_project) | n/a | `string` | `"helixbeat"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for private hosted zone association | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_health_check_id"></a> [health\_check\_id](#output\_health\_check\_id) | Route 53 health check ID for primary ALB (null when created without ALB inputs) |
| <a name="output_private_zone_id"></a> [private\_zone\_id](#output\_private\_zone\_id) | Private Route 53 hosted zone ID |
| <a name="output_public_zone_id"></a> [public\_zone\_id](#output\_public\_zone\_id) | Public Route 53 hosted zone ID |
| <a name="output_public_zone_name_servers"></a> [public\_zone\_name\_servers](#output\_public\_zone\_name\_servers) | Name servers to delegate from your registrar |
<!-- END_TF_DOCS -->