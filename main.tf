data "aws_availability_zones" "available" {
  state = "available"
}
# Create VPC with specified CIDR block
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block

  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
      Name = "${var.environment}-${var.name}-vpc"
    }
  )
}

# Create public subnets across availability zones
resource "aws_subnet" "public_subnet" {
  count                   = var.public_subnet_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  provisioner "local-exec" {
    command = "echo ${self.cidr_block} >> subnets.txt"
  }

  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
      Name = "${var.environment}-${var.name}-public-subnet-${count.index + 1}"
    }
  )
}

# Create private subnets for application tier
resource "aws_subnet" "private_subnet" {
  count             = var.private_subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index + 10)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  provisioner "local-exec" {
    command = "echo ${self.cidr_block} >> subnets.txt"
  }

  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
      Name = "${var.environment}-${var.name}-private-subnet-${count.index + 1}"
    }
  )
}

# Create database subnets in different availability zones
resource "aws_subnet" "db_subnet" {
  count             = var.db_subnet_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index + 20)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  provisioner "local-exec" {
    command = "echo ${self.cidr_block} >> subnets.txt"
  }

  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
      Name = "${var.environment}-${var.name}-db-subnet-${count.index + 1}"
    }
  )
}

# Internet Gateway for public subnet access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
      Name = "${var.environment}-${var.name}-igw"
    }
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
  Name = "${var.environment}-${var.name}-nat-eip" })
}

# NAT Gateway for private subnet outbound connectivity
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
      Name = "${var.environment}-${var.name}-nat-gw"
    }
  )
  depends_on = [aws_internet_gateway.igw]
}

# Route table for public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id
  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
  Name = "${var.environment}-${var.name}-public-route-table" })
}

# Route all public traffic to Internet Gateway
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate public route table to public subnets
resource "aws_route_table_association" "public_route_table_association" {
  count          = var.public_subnet_count
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Route table for private subnets
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
      Name = "${var.environment}-${var.name}-private-route-table"
    }
  )
}

# Route private traffic through NAT Gateway
resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# Associate private route table to private subnets
resource "aws_route_table_association" "private_route_table_association" {
  count          = var.private_subnet_count
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}


# Route table for database subnets
resource "aws_route_table" "db_route_table" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    local.mandatory_tags,
    {
      Name = "${var.environment}-${var.name}-db-route-table"
    }
  )
}

# Route database traffic through NAT Gateway
resource "aws_route" "db_route" {
  route_table_id         = aws_route_table.db_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id

}

# Associate database route table to database subnets
resource "aws_route_table_association" "db_route_table_association" {
  count          = var.db_subnet_count
  subnet_id      = aws_subnet.db_subnet[count.index].id
  route_table_id = aws_route_table.db_route_table.id
}

resource "terraform_data" "list_vpcs" {
  depends_on = [aws_vpc.main]

  triggers_replace = [
    aws_vpc.main.id
  ]

  provisioner "local-exec" {
    command = "aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output text > vpcs.txt"
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "rm -f vpcs.txt subnets.txt"
    on_failure = continue
  }
}