# Networking for the RDS instance and rotation Lambda (created when create_rds = true).
#
# Everything here is fully private: no internet gateway, no NAT gateway.
# The rotation Lambda reaches Secrets Manager, KMS, and CloudWatch Logs via
# VPC interface endpoints instead of going out to the internet.

resource "aws_vpc" "main" {
  count = var.create_rds ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.environment}-secrets-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count = var.create_rds ? length(var.availability_zones) : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.environment}-secrets-private-${var.availability_zones[count.index]}"
    Environment = var.environment
  }
}

# ── Security Groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "lambda" {
  count = var.create_rds ? 1 : 0

  name        = "${var.environment}-rotation-lambda-sg"
  description = "Security group for the secret rotation Lambda"
  vpc_id      = aws_vpc.main[0].id

  egress {
    description = "Allow all outbound traffic (to RDS and VPC endpoints)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-rotation-lambda-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds" {
  count = var.create_rds ? 1 : 0

  name        = "${var.environment}-rds-sg"
  description = "Security group for the RDS instance"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    description     = "PostgreSQL from the rotation Lambda"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-rds-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "vpc_endpoints" {
  count = var.create_rds ? 1 : 0

  name        = "${var.environment}-vpc-endpoints-sg"
  description = "Security group for Secrets Manager / KMS / CloudWatch Logs interface endpoints"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    description     = "HTTPS from the rotation Lambda"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-vpc-endpoints-sg"
    Environment = var.environment
  }
}

# ── VPC Interface Endpoints ──────────────────────────────────────────────────
# Allow the rotation Lambda (in private subnets, no NAT) to reach the AWS APIs
# it needs without traversing the public internet.

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.create_rds ? 1 : 0

  vpc_id              = aws_vpc.main[0].id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.environment}-secretsmanager-endpoint"
    Environment = var.environment
  }
}

resource "aws_vpc_endpoint" "kms" {
  count = var.create_rds ? 1 : 0

  vpc_id              = aws_vpc.main[0].id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.environment}-kms-endpoint"
    Environment = var.environment
  }
}

resource "aws_vpc_endpoint" "logs" {
  count = var.create_rds ? 1 : 0

  vpc_id              = aws_vpc.main[0].id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.environment}-logs-endpoint"
    Environment = var.environment
  }
}
