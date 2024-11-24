locals {
  len_public_subnets  = length(var.public_subnets)
  len_private_subnets = length(var.private_subnets)


  max_subnet_length = local.len_public_subnets
  vpc_id            = aws_vpc.main.id

}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "main" {
  cidr_block = var.ipv4_cidr

  tags = merge(
    { "Name" = var.name },
    var.tags,
  )
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-igw" },
    var.tags,
  )
}

################################################################################
# Publiс Subnets
################################################################################

locals {
  create_public_subnets = local.len_public_subnets > 0
}

resource "aws_subnet" "public" {
  count                = local.create_public_subnets && (local.len_public_subnets >= length(var.azs)) ? local.len_public_subnets : 0
  availability_zone    = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  cidr_block           = element(concat(var.public_subnets, [""]), count.index)
  vpc_id               = local.vpc_id

  tags = merge(
    {
      Name = try(
        format("${var.name}-${var.public_subnet_suffix}-%s", element(var.azs, count.index))
      )
    },
    var.tags,
    var.public_subnet_tags,
  )
}

locals {
  num_public_route_tables = 1
}

resource "aws_route_table" "public" {
  #  count = local.create_public_subnets ? local.num_public_route_tables : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = "${var.name}-${var.public_subnet_suffix}-rt"
    },
    var.tags,
  )
}

resource "aws_route_table_association" "public" {
  count = local.create_public_subnets ? local.len_public_subnets : 0

  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route" "public_internet_gateway" {

  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id

  timeouts {
    create = "5m"
  }
}


################################################################################
# Private Subnets
################################################################################

locals {
  create_private_subnets = local.len_private_subnets > 0
}

resource "aws_subnet" "private" {
  count                = local.create_private_subnets && (local.len_private_subnets >= length(var.azs)) ? local.len_private_subnets : 0
  availability_zone    = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  cidr_block           = element(concat(var.private_subnets, [""]), count.index)
  vpc_id               = local.vpc_id

  tags = merge(
    {
      Name = try(
        format("${var.name}-${var.private_subnet_suffix}-%s", element(var.azs, count.index))
      )
    },
    var.tags,
    var.public_subnet_tags,
  )
}

# There are as many routing tables as the number of NAT gateways
resource "aws_route_table" "private" {
  count = local.create_private_subnets && local.max_subnet_length > 0 ? local.len_private_subnets : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = format(
        "${var.name}-${var.private_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
  )
}

resource "aws_route_table_association" "private" {
  count = local.create_private_subnets ? local.len_private_subnets : 0

  subnet_id = element(aws_subnet.private[*].id, count.index)
  route_table_id = element(
    aws_route_table.private[*].id,
    var.single_nat_gateway ? 0 : count.index,
  )
}

################################################################################
# NAT Gateway
################################################################################

locals {
  nat_gateway_count = var.enable_nat_gateway && var.single_nat_gateway ? 1 : !var.enable_nat_gateway ? 0 : local.max_subnet_length
  nat_gateway_ips   = aws_eip.nat[*].id
}

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  domain = "vpc"

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s",
        element(var.azs, var.single_nat_gateway ? 0 : count.index),
      )
    },
    var.tags,
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = element(
    local.nat_gateway_ips,
    var.single_nat_gateway ? 0 : count.index,
  )
  subnet_id = element(
    aws_subnet.public[*].id,
    var.single_nat_gateway ? 0 : count.index,
  )

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s",
        element(var.azs, var.single_nat_gateway ? 0 : count.index),
      )
    },
    var.tags,
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route" "private_nat_gateway" {
  count = var.enable_nat_gateway ? local.len_private_subnets : 0

  route_table_id         = element(aws_route_table.private[*].id, count.index)
  destination_cidr_block = var.nat_gateway_destination_cidr_block
  nat_gateway_id         = element(aws_nat_gateway.this[*].id, count.index)

  timeouts {
    create = "5m"
  }
}

