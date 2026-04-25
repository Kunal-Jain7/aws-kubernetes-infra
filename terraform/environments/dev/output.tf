# =============================================================================
# environments/dev/outputs.tf
# =============================================================================

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets_ids
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller"
  value       = module.iam.alb_controller_role_arn
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for EBS CSI Driver"
  value       = module.iam.ebs_csi_role_arn
}

output "configure_kubectl" {
  description = "Run this command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
