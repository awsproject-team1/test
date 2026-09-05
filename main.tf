data "aws_iam_policy_document" "sandbox_bucket_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.sandbox.arn,
      "${aws_s3_bucket.sandbox.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket" "sandbox" {
  bucket        = var.sandbox_bucket_name
  force_destroy = false
}

# NOTE: E2E fixture — intentionally disables S3 public-access protections to
# produce an S3-PUBLIC-001 finding for the finding→remediation closed loop.
# Remediation should restore all four flags to true.
resource "aws_s3_bucket_public_access_block" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id
  policy = data.aws_iam_policy_document.sandbox_bucket_tls_only.json
}

# ---------------------------------------------------------------------------
# Consolidated from multiresource.tf.
# Deliberately non-compliant EC2, RDS, and ALB resources for the governance
# platform's customer-sandbox assessment. This is a plan-first test fixture:
# creating it requires the protected apply workflow and explicit human review.
# ---------------------------------------------------------------------------

locals {
  multiresource_name = "kosa-mr-test"
  vpc_cidr           = "10.73.0.0/16"
  availability_zones = length(var.assessment_availability_zones)
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
  availability_zone       = var.assessment_availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.multiresource_name}-public-${count.index + 1}" }

}

resource "aws_subnet" "private" {
  count = local.availability_zones

  vpc_id            = aws_vpc.multiresource.id
  cidr_block        = cidrsubnet(local.vpc_cidr, 8, count.index + 10)
  availability_zone = var.assessment_availability_zones[count.index]

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

# The EC2 AMI is pinned to a resolved ami-... value. Terraform cannot consume
# the EC2/CloudFormation "resolve:ssm:" pseudo-reference in an aws_instance.ami
# argument. The restricted plan role also has no ec2:DescribeImages permission,
# so the AMI cannot be discovered at plan time; the value is supplied via
# image.auto.tfvars.
resource "aws_instance" "assessment" {
  ami           = var.assessment_image_id
  instance_type = "t3.micro"

  # The private subnet intentionally has no Internet route. A public address is
  # still requested so EC2-PUBLIC-IP-001 can evaluate the declared IaC setting.
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  # volume_size must be >= the AMI's root snapshot size (Amazon Linux 2023 is
  # 30 GiB); a smaller value fails RunInstances with InvalidBlockDeviceMapping.
  # encrypted = false is the intentional violation, not the size.
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
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
