# =============================================================================
# modules/iam/main.tf
# Provisions every IAM role EKS needs — kept separate so permission changes
# are reviewed independently of cluster or network changes.
#
# Roles created:
#   eks_cluster_role       — assumed by the EKS control plane
#   eks_node_group_role    — assumed by EC2 worker nodes
#   alb_controller_role    — IRSA for AWS Load Balancer Controller pod
#   ebs_csi_role           — IRSA for EBS CSI Driver pod
#   cluster_autoscaler_role— IRSA for Cluster Autoscaler (optional)
#
# IRSA = IAM Roles for Service Accounts. Pods get scoped AWS credentials
# via OIDC federation — no static credentials needed anywhere.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  # Strip https:// — used as the key prefix in OIDC condition strings
  oidc_issuer = replace(var.oidc_provider_url, "https://", "")
}

# =============================================================================
# EKS CONTROL PLANE ROLE
# =============================================================================
resource "aws_iam_role" "eks-cluster-role" {
  name                 = "${var.cluster_name}-cluster-role"
  description          = "EKS control plane role for ${var.cluster_name}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks-cluster-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks-cluster-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# =============================================================================
# EKS NODE GROUP ROLE
# =============================================================================
resource "aws_iam_role" "eks-node-group-role" {
  name                 = "${var.cluster_name}-node-group-role"
  description          = "EKS worker node role for ${var.cluster_name}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks-node-group-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks-node-group-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_registry_read_only" {
  role       = aws_iam_role.eks-node-group-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Allows connecting to nodes via SSM instead of opening SSH ports
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.eks-node-group-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.eks-node-group-role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# =============================================================================
# IRSA — AWS LOAD BALANCER CONTROLLER
# =============================================================================
resource "aws_iam_role" "alb_controller_role" {
  name        = "${var.cluster_name}-alb-controller-role"
  description = "IRSA role for AWS Load Balancer Controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "alb_controller_policy" {
  name = "${var.cluster_name}-alb-controller-policy"
  role = aws_iam_role.alb_controller_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs", "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups", "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces", "ec2:DescribeTags",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "acm:ListCertificates", "acm:DescribeCertificate",
          "cognito-idp:DescribeUserPoolClient",
          "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:CreateSecurityGroup"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect    = "Allow"
        Action    = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
        Resource  = "*"
        Condition = { Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect    = "Allow"
        Action    = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource  = "*"
        Condition = { Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
      },
      {
        Effect    = "Allow"
        Action    = ["elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:SetIpAddressType", "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets", "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:DeleteTargetGroup"]
        Resource  = "*"
        Condition = { Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:AddListenerCertificates", "elasticloadbalancing:RemoveListenerCertificates", "elasticloadbalancing:ModifyRule"]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# IRSA — EBS CSI DRIVER
# =============================================================================
resource "aws_iam_role" "ebs_csi" {
  name        = "${var.cluster_name}-ebs-csi-role"
  description = "IRSA role for EBS CSI Driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# =============================================================================
# IRSA — CLUSTER AUTOSCALER  (only created when enabled)
# =============================================================================
resource "aws_iam_role" "cluster_autoscaler" {
  count       = var.enable_cluster_autoscaler ? 1 : 0
  name        = "${var.cluster_name}-cluster-autoscaler-role"
  description = "IRSA role for Cluster Autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  name  = "${var.cluster_name}-cluster-autoscaler-policy"
  role  = aws_iam_role.cluster_autoscaler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"             = "true"
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "node_kms_access" {
  name = "${var.cluster_name}-node-kms-policy"
  role = aws_iam_role.eks-node-group-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}
