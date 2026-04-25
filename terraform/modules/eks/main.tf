# =============================================================================
# modules/eks/main.tf  —  FIXED
#
# ROOT CAUSE OF THE ERROR:
# The EBS KMS key policy only granted kms:CreateGrant to ec2.amazonaws.com,
# but EC2 needs to call kms:Decrypt + kms:GenerateDataKey* at instance launch
# time using the **EC2 service principal**, not just the node IAM role.
#
# When Auto Scaling launches a node, the call sequence is:
#   1. Auto Scaling service  → ec2:RunInstances
#   2. EC2 service           → kms:CreateGrant  (to hand off to the instance)
#   3. EC2 service           → kms:Decrypt / kms:GenerateDataKey* (volume attach)
#   4. Node IAM role         → kms:Decrypt / kms:GenerateDataKey* (runtime I/O)
#
# Your old policy blocked step 3 because kms:Decrypt was only granted to
# the node IAM role principal, not to the ec2.amazonaws.com service principal.
# EC2 cannot use the node role — it has its own service principal.
#
# FIXES APPLIED:
#   1. Added kms:Decrypt + kms:GenerateDataKey* to the ec2.amazonaws.com block
#   2. Added autoscaling.amazonaws.com service principal (needed for ASG launch)
#   3. Added explicit allow for the AutoScaling service linked role
#   4. Kept the node IAM role grant for runtime disk I/O
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

data "aws_caller_identity" "current" {}

# =============================================================================
# KMS KEY — EKS Secrets Encryption (unchanged — this was fine)
# =============================================================================
resource "aws_kms_key" "eks_secrets" {
  description             = "EKS secrets encryption for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-secrets-key"
  })
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# =============================================================================
# KMS KEY — EBS Volume Encryption   ← THIS IS WHERE THE BUG WAS
# =============================================================================
resource "aws_kms_key" "ebs" {
  description             = "EBS volume encryption for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # ── 1. Root account — full control (required in every KMS key policy) ──
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },

      # ── 2. EC2 service — needs Decrypt + GenerateDataKey* at launch time ──
      #
      # BUG WAS HERE: your original policy only gave ec2.amazonaws.com the
      # CreateGrant/ListGrants/RevokeGrant actions. That is not enough.
      #
      # When EC2 attaches an encrypted EBS volume it calls:
      #   kms:CreateGrant       → creates a grant for the instance
      #   kms:Decrypt           → decrypts the volume encryption key
      #   kms:GenerateDataKey*  → generates new data keys for writes
      #
      # Without Decrypt and GenerateDataKey* on the SERVICE principal,
      # the launch fails with the exact error you saw.
      {
        Sid    = "AllowEC2ServiceForVolumeEncryption"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },

      # ── 3. Auto Scaling service — needed when ASG launches instances ──
      #
      # Auto Scaling calls EC2 RunInstances on your behalf. It uses the
      # AutoScaling service-linked role, which must also be able to interact
      # with the KMS key to pass volume encryption through to EC2.
      {
        Sid    = "AllowAutoScalingService"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },

      # ── 4. Node IAM role — runtime disk I/O after launch ──
      #
      # This was correct in your original file. The node role needs these
      # permissions for ongoing read/write I/O to the encrypted volume
      # after the instance is running.
      {
        Sid    = "AllowNodeGroupRoleUsage"
        Effect = "Allow"
        Principal = {
          AWS = var.node_group_role_arn
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ebs-key"
  })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.cluster_name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# =============================================================================
# SECURITY GROUPS  (unchanged — these were correct)
# =============================================================================

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS control plane security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "EKS worker nodes security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-nodes-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nodes.id
  security_group_id        = aws_security_group.cluster.id
  description              = "Nodes to API server"
}

resource "aws_security_group_rule" "cluster_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "nodes_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.nodes.id
  description       = "Inter-node communication"
}

resource "aws_security_group_rule" "nodes_ingress_from_cluster_ephemeral" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.nodes.id
  description              = "Control plane to node ephemeral ports"
}

resource "aws_security_group_rule" "nodes_ingress_from_cluster_443" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.nodes.id
  description              = "Control plane webhooks"
}

resource "aws_security_group_rule" "nodes_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nodes.id
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# =============================================================================
# EKS CLUSTER
# =============================================================================
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : []
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
    resources = ["secrets"]
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = var.service_ipv4_cidr
  }

  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  depends_on = [aws_cloudwatch_log_group.cluster]
}

# =============================================================================
# OIDC PROVIDER
# =============================================================================
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-oidc"
  })
}

# =============================================================================
# LAUNCH TEMPLATE
# =============================================================================
resource "aws_launch_template" "node_group" {
  for_each    = var.node_groups
  name_prefix = "${var.cluster_name}-${each.key}-"
  description = "Launch template for node group ${each.key}"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.disk_size_gb
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      kms_key_id            = aws_kms_key.ebs.arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring { enabled = true }

  vpc_security_group_ids = [aws_security_group.nodes.id]

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-${each.key}-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-${each.key}-volume"
    })
  }

  lifecycle { create_before_destroy = true }
}

# =============================================================================
# MANAGED NODE GROUPS
# =============================================================================
resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-${each.key}"
  node_role_arn   = var.node_group_role_arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = each.value.instance_types
  capacity_type   = each.value.capacity_type

  launch_template {
    id      = aws_launch_template.node_group[each.key].id
    version = aws_launch_template.node_group[each.key].latest_version
  }

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = merge({ role = each.key }, each.value.labels)

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(var.tags, {
    Name                                            = "${var.cluster_name}-${each.key}"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  timeouts {
    create = "30m"
    update = "60m"
    delete = "30m"
  }
}

# =============================================================================
# MANAGED ADD-ONS
# =============================================================================
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = var.ebs_csi_role_arn
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_node_group.this]
}
