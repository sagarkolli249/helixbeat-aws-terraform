output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS name (use for Route 53 alias records)"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (use for Route 53 alias records)"
  value       = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "https_listener_arn" {
  description = "HTTPS listener ARN (reference from EKS ingress rules)"
  value       = aws_lb_listener.https.arn
}

output "security_group_id" {
  description = "ALB security group ID (allow from EKS node SG)"
  value       = aws_security_group.alb.id
}

output "default_target_group_arn" {
  value = aws_lb_target_group.default.arn
}
