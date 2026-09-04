# Deliberately non-compliant EC2, RDS, and ALB resources for the governance
# platform's customer-sandbox assessment. This is a plan-first test fixture:
# creating it requires the protected apply workflow and explicit human review.

locals {
  multiresource_name = "kosa-mr-test"
  vpc_cidr           = "10.73.0.0/16"
  availability_zones = 2
}

data "aws_availability_zones" "available" {
  state = "available"
}

# The first plan resolves the current Amazon Linux 2023 image. Before an apply,
# pin the selected AMI ID so the approved commit always produces the same plan.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_vpc" "multiresource" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.multiresource_name}-vpc" }
}

resource "aws_internet_gateway" "multiresource" {
  vpc_id = aws_vpc.multiresource.id
  tags   = { Name = "${local.multiresource_name}-igw" }
}

resource "aws_subnet" "public" {
  count = local.availability_zones

  vpc_id                  = aws_vpc.multiresource.id
  cidr_block              = cidrsubnet(local.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.multiresource_name}-public-${count.index + 1}" }

  lifecycle {
    precondition {
      condition     = length(data.aws_availability_zones.available.names) >= local.availability_zones
      error_message = "The ALB test requires two available Availability Zones."
    }
  }
}

resource "aws_subnet" "private" {
  count = local.availability_zones

  vpc_id            = aws_vpc.multiresource.id
  cidr_block        = cidrsubnet(local.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${local.multiresource_name}-private-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.multiresource.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.multiresource.id
  }

  tags = { Name = "${local.multiresource_name}-public" }
}

resource "aws_route_table_association" "public" {
  count = local.availability_zones

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2" {
  name        = "${local.multiresource_name}-ec2"
  description = "Intentionally broad ingress for governance assessment"
  vpc_id      = aws_vpc.multiresource.id

  ingress {
    description = "Intentional EC2-SG-INGRESS-001 violation"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Intentional unrestricted application ingress"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.multiresource_name}-ec2" }
}

resource "aws_instance" "assessment" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  # The private subnet intentionally has no Internet route. A public address is
  # still requested so EC2-PUBLIC-IP-001 can evaluate the declared IaC setting.
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = false
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "${local.multiresource_name}-ec2" }
}

resource "aws_security_group" "rds" {
  name        = "${local.multiresource_name}-rds"
  description = "Intentionally broad database ingress for governance assessment"
  vpc_id      = aws_vpc.multiresource.id

  ingress {
    description = "Intentional RDS-ACCESS-001 violation"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.multiresource_name}-rds" }
}

resource "aws_db_subnet_group" "assessment" {
  name       = "${local.multiresource_name}-db"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${local.multiresource_name}-db" }
}

resource "aws_db_instance" "assessment" {
  identifier = "${local.multiresource_name}-db"

  engine            = "mysql"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  username                    = "governanceadmin"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.assessment.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible                 = true
  storage_encrypted                   = false
  iam_database_authentication_enabled = false
  enabled_cloudwatch_logs_exports     = []

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  tags = { Name = "${local.multiresource_name}-rds" }
}

resource "aws_security_group" "alb" {
  name        = "${local.multiresource_name}-alb"
  description = "Plain HTTP ingress for governance assessment"
  vpc_id      = aws_vpc.multiresource.id

  ingress {
    description = "Intentional ALB-HTTPS-001 violation"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.multiresource_name}-alb" }
}

resource "aws_lb" "assessment" {
  name               = "${local.multiresource_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # No access_logs block: intentional ALB-LOGGING-001 violation.
  tags = { Name = "${local.multiresource_name}-alb" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.assessment.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "governance test"
      status_code  = "200"
    }
  }

  tags = { Name = "${local.multiresource_name}-http" }
}
