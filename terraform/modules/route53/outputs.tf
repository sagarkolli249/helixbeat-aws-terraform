output "public_zone_id" {
  description = "Public Route 53 hosted zone ID"
  value       = aws_route53_zone.public.zone_id
}

output "public_zone_name_servers" {
  description = "Name servers to delegate from your registrar"
  value       = aws_route53_zone.public.name_servers
}

output "private_zone_id" {
  description = "Private Route 53 hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "health_check_id" {
  description = "Route 53 health check ID for primary ALB (null when created without ALB inputs)"
  value       = length(aws_route53_health_check.primary) > 0 ? aws_route53_health_check.primary[0].id : null
}
