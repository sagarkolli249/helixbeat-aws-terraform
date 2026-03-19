output "security_group_id" {
  description = "EC2 instance security group ID (allow from DocumentDB, EFS)"
  value       = aws_security_group.ec2.id
}

output "instance_role_arn" {
  value = aws_iam_role.ec2.arn
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.ec2.name
}

output "launch_template_id" {
  value = aws_launch_template.this.id
}

output "asg_name" {
  value = aws_autoscaling_group.this.name
}
