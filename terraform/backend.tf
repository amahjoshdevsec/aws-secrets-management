terraform {
  required_version = ">= 1.5"

  # ── CHANGE THESE THREE VALUES ─────────────────────────────────────────────
  # bucket         → name of YOUR S3 bucket for Terraform state
  #                  Must exist before running `terraform init`
  #                  Create it: aws s3api create-bucket --bucket <your-bucket> --region <your-region>
  #
  # region         → AWS region where your S3 bucket lives
  #
  # dynamodb_table → name of YOUR DynamoDB table for state locking
  #                  Must have a partition key named "LockID" (type String)
  #                  Create it: aws dynamodb create-table \
  #                    --table-name <your-table> \
  #                    --attribute-definitions AttributeName=LockID,AttributeType=S \
  #                    --key-schema AttributeName=LockID,KeyType=HASH \
  #                    --billing-mode PAY_PER_REQUEST
  # ──────────────────────────────────────────────────────────────────────────
  backend "s3" {
    bucket         = "aj-cloudsentrics-bucket" # CHANGE: your S3 bucket name
    key            = "secrets-management/terraform.tfstate"
    region         = "us-east-1"               # CHANGE: your AWS region
    dynamodb_table = "my-lock-table"           # CHANGE: your DynamoDB table name
    encrypt        = true
  }
}
