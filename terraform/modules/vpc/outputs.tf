output "vpc_id" {
  value = aws_vpc.client-vpc.id
}

output "vpc_cidr_block" {
  value = aws_vpc.client-vpc.cidr_block
}

output "public_subnets_ids" {
  value = aws_subnet.client-pub-sub[*].id
}

output "private_subnets_ids" {
  value = aws_subnet.client-prv-sub[*].id
}

output "availability_zones" {
  value = local.azs
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.client-nat[*].id
}
