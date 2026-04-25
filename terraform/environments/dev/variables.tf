variable "project_name" {
  type = string
}

variable "owner" {
  type = string
}

variable "cost_center" {
  type = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster (e.g. '1.33')."
  type        = string
  default     = "1.33"
}

variable "cidr_block" {
  description = "CIDR block for the dev VPC. Must not overlap with prod."
  type        = string
  default     = "10.1.0.0/16"
}

variable "service_ipv4_cidr" {
  description = "CIDR block for Kubernetes service IPs."
  type        = string
  default     = "172.20.0.0/16"
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}
