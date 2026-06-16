# RDS PostgreSQL instance (created when create_rds = true).
#
# The master password is generated here with random_password and seeded
# into the Secrets Manager secret in secrets.tf. From that point on, the
# rotation Lambda owns the password — Terraform never reads it back.

resource "random_password" "db_master_password" {
  count = var.create_rds ? 1 : 0

  length  = 32
  special = true
  # Avoid characters that commonly cause issues in connection strings/shells.
  override_special = "!#$%^&*()-_=+"
}

resource "aws_db_subnet_group" "main" {
  count = var.create_rds ? 1 : 0

  name       = "${var.environment}-secrets-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Environment = var.environment
  }
}

resource "aws_db_instance" "app_db" {
  count = var.create_rds ? 1 : 0

  identifier     = "${var.environment}-app-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage      = var.db_allocated_storage
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_key[0].arn
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_master_password[0].result
  db_subnet_group_name   = aws_db_subnet_group.main[0].name
  vpc_security_group_ids = [aws_security_group.rds[0].id]

  publicly_accessible     = false
  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
