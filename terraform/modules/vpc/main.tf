# =============================================================================
# modules/vpc/main.tf
# Provisions: VPC, public subnets, private subnets, Internet Gateway,
#             NAT Gateways (one per AZ), route tables, VPC Flow Logs.
# =============================================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Fetching available AZs in the region to distribute subnets across them
data "aws_availability_zones" "available" {
  state = "available"
}

# slice() is used to take a subset of the AZ list. slice(list, start_index, end_index), Start from index 0, Take up to var.az_count
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "client-vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name                                        = "${var.name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "client-igw" {
  vpc_id = aws_vpc.client-vpc.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

# -----------------------------------------------------------------------------
# Public Subnets  (one per AZ — for ALB and NAT Gateways)
# -----------------------------------------------------------------------------

resource "aws_subnet" "client-pub-sub" {
  count = var.az_count

  vpc_id                  = aws_vpc.client-vpc.id
  availability_zone       = local.azs[count.index]                     # local.azs = ["ap-south-1a", "ap-south-1b"], then count.index = 0 → ap-south-1a, count.index = 1 → ap-south-1b
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index) # This function divides the VPC CIDR block into smaller subnets. The second argument (8) specifies the new subnet mask, and the third argument (count.index) determines which subnet to create based on the index. If var.vpc_cidr = "10.0.0.0/16", then count.index = 0 → 10.0.0.0/24, count.index = 1 → 10.0.1.0/24, count.index = 2 → 10.0.2.0/24
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${local.azs[count.index]}"
  })
}

# -----------------------------------------------------------------------------
# Private Subnets  (one per AZ — for EKS nodes and pods)
# -----------------------------------------------------------------------------

resource "aws_subnet" "client-prv-sub" {
  count = var.az_count

  vpc_id            = aws_vpc.client-vpc.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index + 10) # This function divides the VPC CIDR block into smaller subnets. The second argument (8) specifies the new subnet mask, and the third argument (count.index + 10) determines which subnet to create based on the index. If var.vpc_cidr = "

  tags = merge(var.tags, {
    Name                                        = "${var.name}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# -----------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
# -----------------------------------------------------------------------------
resource "aws_eip" "client-eip" {
  count      = var.az_count
  domain     = "vpc"
  depends_on = [aws_internet_gateway.client-igw]

  tags = merge(var.tags, {
    Name = "${var.name}-eip-${local.azs[count.index]}"
  })
}

# -----------------------------------------------------------------------------
# NAT Gateways  (one per AZ — losing one AZ must not kill outbound traffic)
# -----------------------------------------------------------------------------
resource "aws_nat_gateway" "client-nat" {
  count         = var.az_count
  allocation_id = aws_eip.client-eip[count.index].id
  subnet_id     = aws_subnet.client-pub-sub[count.index].id
  depends_on    = [aws_internet_gateway.client-igw]

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${local.azs[count.index]}"
  })
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------
resource "aws_route_table" "client-pub-rt" {
  vpc_id = aws_vpc.client-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.client-igw.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-pub-rt"
  })
}

resource "aws_route_table" "client-prv-rt" {
  count  = var.az_count
  vpc_id = aws_vpc.client-vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.client-nat[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-prv-rt-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "client-pub-assoc" {
  count          = var.az_count
  subnet_id      = aws_subnet.client-pub-sub[count.index].id
  route_table_id = aws_route_table.client-pub-rt.id
}


resource "aws_route_table_association" "vlient-prv-assoc" {
  count          = var.az_count
  subnet_id      = aws_subnet.client-prv-sub[count.index].id
  route_table_id = aws_route_table.client-prv-rt[count.index].id
}

# -----------------------------------------------------------------------------
# VPC Flow Logs  → CloudWatch
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow-logs-lg" {
  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_iam_role" "flow-logs-role" {
  name = "${var.name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow-logs-policy" {
  name = "${var.name}-flow-logs-policy"
  role = aws_iam_role.flow-logs-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.flow-logs-lg.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "flow-logs" {
  vpc_id          = aws_vpc.client-vpc.id
  log_destination = aws_cloudwatch_log_group.flow-logs-lg.arn
  iam_role_arn    = aws_iam_role.flow-logs-role.arn
  traffic_type    = "ALL"

  tags = merge(var.tags, {
    Name = "${var.name}-flow-logs"
  })
}
