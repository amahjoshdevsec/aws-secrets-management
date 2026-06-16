variable "aws_region" {
  description = "AWS region to deploy resources into"
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (used to prefix/tag resources)"
  default     = "prod"
}

# ── RDS / Networking ──────────────────────────────────────────────────────────

variable "create_rds" {
  description = "If true, provision a new VPC + private RDS PostgreSQL instance for this project. If false, the rotation Lambda is wired up to use the 'existing_*' variables instead."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC created when create_rds = true"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for the private subnets (RDS requires at least 2 for its subnet group)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "db_instance_class" {
  description = "RDS instance class (used when create_rds = true)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version (used when create_rds = true)"
  type        = string
  default     = "16.4"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB (used when create_rds = true)"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Database name (used when create_rds = true)"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username (used when create_rds = true)"
  type        = string
  default     = "app_user"
}

# ── Existing RDS (used only when create_rds = false) ────────────────────────────

variable "existing_db_host" {
  description = "Endpoint/host of an existing RDS instance (required when create_rds = false)"
  type        = string
  default     = ""
}

variable "existing_db_port" {
  description = "Port of an existing RDS instance (used when create_rds = false)"
  type        = number
  default     = 5432
}

variable "existing_db_name" {
  description = "Database name on an existing RDS instance (used when create_rds = false)"
  type        = string
  default     = ""
}

variable "existing_db_username" {
  description = "Master username on an existing RDS instance (used when create_rds = false)"
  type        = string
  default     = ""
}

variable "existing_db_password" {
  description = "Master password on an existing RDS instance (used when create_rds = false). Only used to seed the initial secret version; rotation takes over afterwards."
  type        = string
  default     = ""
  sensitive   = true
}

variable "existing_lambda_subnet_ids" {
  description = "Private subnet IDs the rotation Lambda should run in to reach an existing RDS instance (required when create_rds = false)"
  type        = list(string)
  default     = []
}

variable "existing_lambda_security_group_ids" {
  description = "Security group IDs to attach to the rotation Lambda when create_rds = false. The existing RDS security group must allow inbound access from this SG."
  type        = list(string)
  default     = []
}

# ── Rotation Lambda ───────────────────────────────────────────────────────────

