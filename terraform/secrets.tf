locals {
  db_host     = var.create_rds ? aws_db_instance.app_db[0].address : var.existing_db_host
  db_port     = var.create_rds ? aws_db_instance.app_db[0].port : var.existing_db_port
  db_name_val = var.create_rds ? var.db_name : var.existing_db_name
  db_username = var.create_rds ? var.db_username : var.existing_db_username
  db_password = var.create_rds ? random_password.db_master_password[0].result : var.existing_db_password
}

# Database credentials secret
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.environment}/database/credentials"
  kms_key_id              = aws_kms_key.secrets_key.arn
  recovery_window_in_days = 30

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials_value" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = local.db_username
    password = local.db_password # Initial value only - the rotation Lambda owns this afterwards
    host     = local.db_host
    port     = local.db_port
    dbname   = local.db_name_val
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# API key secret
resource "aws_secretsmanager_secret" "stripe_api_key" {
  name                    = "${var.environment}/api/stripe"
  kms_key_id              = aws_kms_key.secrets_key.arn
  recovery_window_in_days = 30

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
