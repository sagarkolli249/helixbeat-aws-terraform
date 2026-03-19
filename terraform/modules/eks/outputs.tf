output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.this.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "node_role_arn" {
  description = "ARN of the node IAM role"
  value       = aws_iam_role.nodes.arn
}

output "node_security_group_id" {
  description = "Security group ID for node groups"
  value       = aws_security_group.nodes.id
}

output "cluster_kms_key_arn" {
  description = "KMS key ARN used for EKS secret encryption"
  value       = aws_kms_key.eks.arn
}

output "ecr_repository_urls" {
  description = "Map of ECR repository names to URLs"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}
