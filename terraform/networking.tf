# Find all VPCs with the app name
data "aws_vpcs" "matching" {
  count = var.use_existing_vpc ? 1 : 0
  tags = {
    Name = "${var.app_name}-vpc"
  }
}

# Get details of the existing VPC if found
data "aws_vpc" "existing" {
  count = var.use_existing_vpc && length(data.aws_vpcs.matching) > 0 && length(data.aws_vpcs.matching[0].ids) > 0 ? 1 : 0
  id    = data.aws_vpcs.matching[0].ids[0]

  filter {
    name   = "tag:Name"
    values = ["${var.app_name}-vpc"]
  }

  filter {
    name   = "isDefault"
    values = ["false"]
  }
}

# Create a new VPC if not using an existing one or if the existing one is not found
resource "aws_vpc" "main" {
  count                = !var.use_existing_vpc || (length(data.aws_vpcs.matching) > 0 && length(data.aws_vpcs.matching[0].ids) == 0) ? 1 : 0
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    {
      Name = "${var.app_name}-vpc"
    },
    local.common_tags
  )

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
    ignore_changes = [
      # Ignore changes to tags, e.g. because a management agent
      # updates these based on some ruleset managed elsewhere.
      tags,
    ]
  }
}

# Determine the VPC ID based on what's available
locals {
  # Use existing VPC if found, otherwise use the newly created one
  vpc_id = (
    var.use_existing_vpc &&
    length(data.aws_vpcs.matching) > 0 &&
    length(data.aws_vpcs.matching[0].ids) > 0 &&
    length(data.aws_vpc.existing) > 0 ?
    data.aws_vpc.existing[0].id :
    (length(aws_vpc.main) > 0 ? aws_vpc.main[0].id : null)
  )

  # This will cause a clear error if no VPC is available
  vpc_id_validation = local.vpc_id != null ? true : tobool("Failed to find or create a VPC. Please check your configuration.")
}

# Find existing subnets if using existing VPC
data "aws_subnets" "existing_public" {
  count = var.use_existing_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.app_name}-public-*"]
  }
}

# Create new subnets only if not using existing ones
resource "aws_subnet" "public" {
  count                   = var.use_existing_vpc ? 0 : 2
  vpc_id                  = local.vpc_id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-public-${count.index}"
  }
}

# Use either existing or new subnets
locals {
  public_subnet_ids = var.use_existing_vpc ? data.aws_subnets.existing_public[0].ids : aws_subnet.public[*].id
}

# Find existing IGW if using existing VPC
data "aws_internet_gateway" "existing" {
  count = var.use_existing_vpc && var.create_igw ? 1 : 0

  filter {
    name   = "attachment.vpc-id"
    values = [local.vpc_id]
  }

  # Don't fail if no IGW is found
  lifecycle {
    postcondition {
      condition     = self.id != ""
      error_message = "No Internet Gateway found in VPC ${local.vpc_id}. Set create_igw to true to create one."
    }
  }
}

# Create IGW if we're not using an existing VPC or explicitly told to create one
resource "aws_internet_gateway" "main" {
  count  = var.create_igw ? 1 : 0
  vpc_id = local.vpc_id

  tags = {
    Name = "${var.app_name}-igw"
  }

  # Ensure we don't try to create if one already exists
  lifecycle {
    ignore_changes = [vpc_id]
  }
}

# Use either existing or new IGW, or none if not needed
locals {
  igw_id = var.use_existing_vpc ? (
    # If using existing VPC and create_igw is true, try to use existing IGW or create a new one
    var.create_igw ? (
      length(data.aws_internet_gateway.existing) > 0 && data.aws_internet_gateway.existing[0].id != "" ?
      data.aws_internet_gateway.existing[0].id :
      (length(aws_internet_gateway.main) > 0 ? aws_internet_gateway.main[0].id : null)
    ) : null # If create_igw is false, don't use any IGW
    ) : (
    # For new VPCs, use the created IGW if it exists
    length(aws_internet_gateway.main) > 0 ? aws_internet_gateway.main[0].id : null
  )
}

# Find existing route table if using existing VPC
data "aws_route_tables" "existing_public" {
  count  = var.use_existing_vpc ? 1 : 0
  vpc_id = local.vpc_id

  filter {
    name   = "tag:Name"
    values = ["${var.app_name}-public-rt"]
  }
}

# Create new route table only if not using existing one
resource "aws_route_table" "public" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.igw_id
  }

  tags = {
    Name = "${var.app_name}-public-rt"
  }
}

# Create route table associations for new subnets
resource "aws_route_table_association" "public" {
  for_each = var.use_existing_vpc ? toset([]) : toset([for i, _ in aws_subnet.public : tostring(i)])

  subnet_id      = aws_subnet.public[tonumber(each.key)].id
  route_table_id = aws_route_table.public[0].id
}

# Use either existing or new route table ID
locals {
  public_route_table_id = var.use_existing_vpc ? (
    length(data.aws_route_tables.existing_public) > 0 && length(data.aws_route_tables.existing_public[0].ids) > 0 ?
    data.aws_route_tables.existing_public[0].ids[0] :
    (var.create_igw ? (length(aws_internet_gateway.main) > 0 ? aws_internet_gateway.main[0].id : null) : null)
  ) : (
    var.create_igw && length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : null
  )
}

resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-sg"
  description = "Allow HTTP/HTTPS traffic"
  vpc_id      = local.vpc_id

  # Ingress rules
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP access from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS access from anywhere"
  }

  # Egress rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # Standard tags merged with common tags
  tags = merge(
    {
      Name        = "${var.app_name}-alb-sg"
      Description = "Security group for ${var.app_name} ALB"
    },
    local.common_tags
  )

  # Lifecycle rules
  lifecycle {
    create_before_destroy = true

    # Ignore changes to tags that might be managed by external tools
    ignore_changes = [
      tags,
      description,
    ]
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.app_name}-ecs-tasks-sg"
  description = "Allow inbound access from the ALB only"
  vpc_id      = local.vpc_id

  # Ingress rule - only allow traffic from ALB
  ingress {
    protocol        = "tcp"
    from_port       = var.app_port
    to_port         = var.app_port
    security_groups = [aws_security_group.alb.id]
    description     = "Allow traffic from ALB to ECS tasks"
  }

  # Egress rule - allow all outbound traffic
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # Standard tags merged with common tags
  tags = merge(
    {
      Name        = "${var.app_name}-ecs-tasks-sg"
      Description = "Security group for ${var.app_name} ECS tasks"
    },
    local.common_tags
  )

  # Lifecycle rules
  lifecycle {
    create_before_destroy = true

    # Prevent deletion of this security group if it's in use
    prevent_destroy = false # Set to true in production after initial deployment

    # Ignore changes to tags that might be managed by external tools
    ignore_changes = [
      tags,
      description,
    ]
  }
}
