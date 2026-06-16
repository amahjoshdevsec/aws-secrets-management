# KMS key used to encrypt secrets stored in Secrets Manager.
# A customer-managed key (rather than the default aws/secretsmanager key)
# gives us a separate, auditable encryption layer with its own key policy
# and rotation schedule.

resource "aws_kms_key" "secrets_key" {
  description             = "KMS key for Secrets Manager encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    Purpose     = "secrets-encryption"
  }
}

resource "aws_kms_alias" "secrets_key_alias" {
  name          = "alias/${var.environment}/secrets-manager"
  target_key_id = aws_kms_key.secrets_key.key_id
}

# Separate KMS key for RDS storage encryption (used when create_rds = true).
# Kept separate from the secrets key so each has its own key policy and
# rotation schedule, and so RDS access doesn't imply Secrets Manager access.

resource "aws_kms_key" "rds_key" {
  count = var.create_rds ? 1 : 0

  description             = "KMS key for RDS storage encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    Purpose     = "rds-encryption"
  }
}

resource "aws_kms_alias" "rds_key_alias" {
  count = var.create_rds ? 1 : 0

  name          = "alias/${var.environment}/rds-storage"
  target_key_id = aws_kms_key.rds_key[0].key_id
}
