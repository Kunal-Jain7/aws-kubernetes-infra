# =============================================================================
# modules/eks/variables.tf
# =============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to run on the EKS cluster (e.g. '1.33')."
  type        = string
  default     = "1.33"
}

variable "vpc_id" {
  description = "ID of the VPC — output by the vpc module."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for worker nodes — output by the vpc module."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs added to the cluster VPC config (for ENIs)."
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane — output by the iam module."
  type        = string
}

variable "node_group_role_arn" {
  description = "IAM role ARN for worker nodes — output by the iam module."
  type        = string
}

variable "ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI driver — output by the iam module."
  type        = string
}

variable "endpoint_public_access" {
  description = "Expose the EKS API server endpoint publicly. Set false for fully private clusters."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Always restrict in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "service_ipv4_cidr" {
  description = "CIDR block for Kubernetes service IPs. Must not overlap with the VPC CIDR."
  type        = string
  default     = "172.20.0.0/16"
}

variable "log_retention_days" {
  description = "Days to retain EKS control plane logs in CloudWatch."
  type        = number
  default     = 30
}

variable "node_groups" {
  description = "Map of managed node group configurations. Key = node group name."
  type = map(object({
    instance_types = list(string)
    capacity_type  = string # "ON_DEMAND" or "SPOT"
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size_gb   = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string # NO_SCHEDULE | NO_EXECUTE | PREFER_NO_SCHEDULE
    }))
  }))
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
