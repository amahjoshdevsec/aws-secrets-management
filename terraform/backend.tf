terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "aj-cloudsentrics-bucket"
    key            = "secrets-management/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "my-lock-table"
    encrypt        = true
  }
}
