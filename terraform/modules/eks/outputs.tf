# =============================================================================
# modules/eks/outputs.tf
# =============================================================================

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.this.version
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — passed to the iam module for IRSA"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider — passed to the iam module for IRSA"
  value       = aws_iam_openid_connect_provider.this.url
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID attached to worker nodes"
  value       = aws_security_group.nodes.id
}

output "ebs_kms_key_arn" {
  description = "ARN of the KMS key used for EBS volume encryption"
  value       = aws_kms_key.ebs.arn
}

output "secrets_kms_key_arn" {
  description = "ARN of the KMS key used for Kubernetes secrets encryption"
  value       = aws_kms_key.eks_secrets.arn
}

output "node_group_names" {
  description = "Names of all created managed node groups"
  value       = { for k, v in aws_eks_node_group.this : k => v.node_group_name }
}
