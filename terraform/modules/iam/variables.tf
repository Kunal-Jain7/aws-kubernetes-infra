# =============================================================================
# modules/iam/variables.tf
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name — used as a prefix on every IAM resource."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider — output by the eks module."
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider — output by the eks module."
  type        = string
}

variable "enable_cluster_autoscaler" {
  description = "Set to true to create the IRSA role for Cluster Autoscaler."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
