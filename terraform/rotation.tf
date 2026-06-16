# Build the Lambda deployment package locally before zipping.
# psycopg2-binary needs to be compiled for Linux/x86_64 (the Lambda OS).
# pip's --platform flag lets us download the correct wheel on any OS without Docker.
resource "null_resource" "build_lambda_package" {
  triggers = {
    source_hash = filesha256("${path.module}/../examples/secure/rotation-lambda.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/lambda_package
      mkdir -p ${path.module}/lambda_package
      pip3 install psycopg2-binary==2.9.9 \
        --target ${path.module}/lambda_package \
        --platform manylinux2014_x86_64 \
        --python-version 3.11 \
        --only-binary=:all: \
        --quiet
      cp ${path.module}/../examples/secure/rotation-lambda.py \
         ${path.module}/lambda_package/rotation-lambda.py
    EOT
  }
}

data "archive_file" "rotation_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_package"
  output_path = "${path.module}/rotation-lambda.zip"
  depends_on  = [null_resource.build_lambda_package]
}

locals {
  rotation_lambda_subnet_ids         = var.create_rds ? aws_subnet.private[*].id : var.existing_lambda_subnet_ids
  rotation_lambda_security_group_ids = var.create_rds ? [aws_security_group.lambda[0].id] : var.existing_lambda_security_group_ids
}

resource "aws_lambda_function" "secret_rotation" {
  filename         = data.archive_file.rotation_lambda_zip.output_path
  function_name    = "${var.environment}-secret-rotation"
  role             = aws_iam_role.rotation_lambda_role.arn
  handler          = "rotation-lambda.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.rotation_lambda_zip.output_base64sha256
  timeout          = 30

  vpc_config {
    subnet_ids         = local.rotation_lambda_subnet_ids
    security_group_ids = local.rotation_lambda_security_group_ids
  }

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.rotation_lambda_vpc_access]
}

resource "aws_lambda_permission" "allow_secrets_manager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}

resource "aws_secretsmanager_secret_rotation" "db_rotation" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_lambda_permission.allow_secrets_manager]
}
