provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

# -----------------------------------------------------------------------------
# Locals — single source of truth for names and tags
# -----------------------------------------------------------------------------
locals {
  env          = "dev"
  cluster_name = "${var.project_name}-${local.env}"

  common_tags = {
    Project     = var.project_name
    Environment = local.env
    ManagedBy   = "Terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# -----------------------------------------------------------------------------
# Module: VPC
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  name               = local.cluster_name
  cluster_name       = local.cluster_name
  cidr_block         = var.cidr_block
  az_count           = 2
  log_retention_days = 7
  tags               = local.common_tags
}


# -----------------------------------------------------------------------------
# Module: EKS  (cluster + OIDC provider — needed before IAM IRSA roles)
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets_ids
  public_subnet_ids  = module.vpc.public_subnets_ids

  cluster_role_arn    = module.iam.eks_cluster_role_arn
  node_group_role_arn = module.iam.eks_node_group_role_arn
  ebs_csi_role_arn    = module.iam.ebs_csi_role_arn

  # Dev: open endpoint for easy kubectl access from any IP
  endpoint_public_access = true
  public_access_cidrs    = ["0.0.0.0/0"]

  service_ipv4_cidr  = var.service_ipv4_cidr
  log_retention_days = 7
  tags               = local.common_tags

  node_groups = {
    general = {
      instance_types = ["c7i-flex.large"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      disk_size_gb   = 20
      labels         = { role = "general" }
      taints         = []
    }
  }
}

# -----------------------------------------------------------------------------
# Module: IAM  (depends on EKS OIDC output for IRSA roles)
# -----------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  cluster_name              = local.cluster_name
  oidc_provider_arn         = module.eks.oidc_provider_arn
  oidc_provider_url         = module.eks.oidc_provider_url
  enable_cluster_autoscaler = false

  tags = local.common_tags
}
