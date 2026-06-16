data "aws_caller_identity" "current" {}

# ── Web Application Role ──────────────────────────────────────────────────────
resource "aws_iam_role" "web_app_role" {
  name = "${var.environment}-web-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Production: EC2 instances assume this role via instance profile
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
      {
        # Testing: allows any IAM user/role in this account with
        # sts:AssumeRole permission to assume this role from the CLI
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "web_app_secrets_policy" {
  name = "${var.environment}-web-app-secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = aws_secretsmanager_secret.db_credentials.arn
        # Only this one secret, nothing else
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.secrets_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "web_app_attach" {
  role       = aws_iam_role.web_app_role.name
  policy_arn = aws_iam_policy.web_app_secrets_policy.arn
}

# ── Lambda Rotation Role ──────────────────────────────────────────────────────
resource "aws_iam_role" "rotation_lambda_role" {
  name = "${var.environment}-rotation-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "rotation_lambda_policy" {
  name = "${var.environment}-rotation-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = aws_kms_key.secrets_key.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rotation_attach" {
  role       = aws_iam_role.rotation_lambda_role.name
  policy_arn = aws_iam_policy.rotation_lambda_policy.arn
}

# Required for the Lambda to run inside the VPC and reach RDS:
# grants ec2:CreateNetworkInterface / DescribeNetworkInterfaces / DeleteNetworkInterface.
resource "aws_iam_role_policy_attachment" "rotation_lambda_vpc_access" {
  role       = aws_iam_role.rotation_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
