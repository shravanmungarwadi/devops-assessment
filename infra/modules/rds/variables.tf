variable "project" {
  description = "Project name, used for tagging and resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "engine" {
  description = "Database engine: postgres or mysql"
  type        = string
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "engine must be either \"postgres\" or \"mysql\"."
  }
}

variable "engine_version" {
  description = "Database engine version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class (size). Smaller for dev, bigger for prod."
  type        = string
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "app_admin"
}

variable "db_password" {
  description = "Master password for the database. Pass via a secret manager / TF_VAR in real usage, never commit it."
  type        = string
  sensitive   = true
}

variable "port" {
  description = "Port the database listens on"
  type        = number
  default     = 5432
}

variable "private_subnet_ids" {
  description = "Private subnet IDs the RDS subnet group should span"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "Security group IDs to attach to the RDS instance"
  type        = list(string)
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups. Shorter for dev, longer for prod."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection. false for dev, true for prod."
  type        = bool
  default     = false
}

variable "multi_az" {
  description = "Whether to deploy a Multi-AZ standby replica. Usually false for dev, true for prod."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot on destroy. true for dev convenience, false for prod safety."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
