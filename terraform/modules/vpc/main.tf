resource "aws_vpc" "client-vpc" {
  cidr_block = var.cidr_block

  tags = {
    Name = "${var.env}-vpc"
  }
}

resource "aws_internet_gateway" "client-igw" {
  vpc_id = aws_vpc.client-vpc.id

  tags = {
    Name = "${var.env}-igw"
  }
}

resource "aws_subnet" "client-pub-sub" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.client-vpc.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.public_subnets[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.env}-pub-sub-${count.index + 1}"
  }
}

resource "aws_subnet" "client-prv-sub" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.client-vpc.id
  availability_zone = var.azs[count.index]
  cidr_block        = var.private_subnets[count.index]

  tags = {
    Name = "${var.env}-prv-sub-${count.index + 1}"
  }
}

resource "aws_eip" "client-eip" {
  depends_on = [aws_internet_gateway.client-igw]

  tags = {
    Name = "${var.env}-eip"
  }
}

resource "aws_nat_gateway" "client-nat" {
  allocation_id = aws_eip.client-eip.id
  subnet_id     = aws_subnet.client-pub-sub[0].id

  tags = {
    Name = "${var.env}-nat"
  }
}

resource "aws_route_table" "client-pub-rt" {
  vpc_id = aws_vpc.client-vpc.id

  tags = {
    Name = "${var.env}-pub-rt"
  }
}

resource "aws_route" "public-route" {
  route_table_id         = aws_route_table.client-pub-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.client-igw.id
}

resource "aws_route_table_association" "client-pub-assoc" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.client-pub-sub[count.index].id
  route_table_id = aws_route_table.client-pub-rt.id
}

resource "aws_route_table" "client-prv-rt" {
  vpc_id = aws_vpc.client-vpc.id

  tags = {
    Name = "${var.env}-prv-rt"
  }
}

resource "aws_route" "private-route" {
  route_table_id         = aws_route_table.client-prv-rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.client-nat.id
}

resource "aws_route_table_association" "vlient-prv-assoc" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.client-prv-sub[count.index].id
  route_table_id = aws_route_table.client-prv-rt.id
}
