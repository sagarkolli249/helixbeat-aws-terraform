output "cluster_endpoint" {
  description = "DocumentDB writer endpoint"
  value       = aws_docdb_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "DocumentDB reader endpoint"
  value       = aws_docdb_cluster.this.reader_endpoint
}

output "cluster_port" {
  value = aws_docdb_cluster.this.port
}

output "cluster_id" {
  value = aws_docdb_cluster.this.cluster_identifier
}

output "security_group_id" {
  value = aws_security_group.docdb.id
}

output "credentials_secret_arn" {
  description = "Secrets Manager ARN for DocumentDB master credentials"
  value       = aws_secretsmanager_secret.docdb_master.arn
}

output "credentials_secret_name" {
  value = aws_secretsmanager_secret.docdb_master.name
}
