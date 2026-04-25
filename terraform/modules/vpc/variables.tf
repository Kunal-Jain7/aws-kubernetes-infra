# =============================================================================
# modules/vpc/variables.tf
# =============================================================================
variable "name" {
  type        = string
  description = "Prefix applied to every resource name created by this module."
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name — used in Kubernetes subnet-discovery tags."
}

variable "cidr_block" {
  type = string

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to use. 2 for dev, 3 for prod."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Days to retain VPC Flow Logs in CloudWatch."
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}

