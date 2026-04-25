# =============================================================================
# modules/iam/outputs.tf
# =============================================================================

output "eks_cluster_role_arn" {
  value = aws_iam_role.eks-cluster-role.arn
}

output "eks_node_group_role_arn" {
  value = aws_iam_role.eks-node-group-role.arn
}

output "eks_node_group_name" {
  value = aws_iam_role.eks-node-group-role.name
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller_role.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

output "cluster_autoscaler_role_arn" {
  value = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler[0].arn : ""
}
