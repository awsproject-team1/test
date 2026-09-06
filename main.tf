# =============================================================================
# DEMO FIXTURE — intentionally non-compliant across S3/EC2/RDS/ALB.
# 격리된 sandbox 계정 전용. 거버넌스 폐루프(위반→Finding→조치→재평가) 시연용.
# 시연 후 반드시 `terraform destroy`로 정리한다. 프로덕션에 두지 않는다.
# =============================================================================

resource "aws_s3_bucket" "sandbox" {
  bucket        = var.sandbox_bucket_name
  force_destroy = true
}

# S3-PUBLIC-001 위반: 네 플래그 모두 false → Block Public Access 해제.
resource "aws_s3_bucket_public_access_block" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3-ACL-001 위반: ObjectWriter는 ACL 기반 접근을 허용한다(BucketOwnerEnforced 아님).
resource "aws_s3_bucket_ownership_controls" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

# S3-ENCRYPT-001 위반: 서버 측 암호화 구성을 두지 않는다(리소스 제거).
# S3-TLS-001 위반: TLS 강제 bucket policy를 두지 않는다(리소스 제거).
# S3-LOGGING-001 위반: 서버 액세스 로깅을 두지 않는다.

# ---------------------------------------------------------------------------
# EC2 / RDS / ALB — 의도적 위반. plan-first fixture: 생성에는 보호된 apply
# workflow와 사람 검토가 필요하다.
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

  # EC2-SG-INGRESS-001 위반: SSH/HTTP를 0.0.0.0/0에 개방.
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
  ami           = var.assessment_image_id
  instance_type = "t3.micro"

  # EC2-PUBLIC-IP-001 위반: 프라이빗 서브넷 인스턴스에 퍼블릭 IP 요청.
  subnet_id                   = aws_subnet.private[0].id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  # EC2-EBS-ENCRYPT-001 위반: 루트 볼륨 미암호화.
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

  # RDS-ACCESS-001 위반: 3306을 0.0.0.0/0에 개방.
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

  # RDS-PUBLIC-001 위반: 퍼블릭 액세스 노출.
  publicly_accessible = true
  # RDS-ENCRYPT-001 위반: 저장 데이터 미암호화.
  storage_encrypted                   = false
  iam_database_authentication_enabled = false
  # RDS-LOGGING-001 위반: 로그 export 없음.
  enabled_cloudwatch_logs_exports = []

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

  # ALB-LOGGING-001 위반: access_logs 블록 없음.
  tags = { Name = "${local.multiresource_name}-alb" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.assessment.arn
  port              = 80
  protocol          = "HTTP"

  # ALB-HTTPS-001 위반: HTTPS가 아닌 평문 HTTP 리스너.
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
