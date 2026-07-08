variable "project" {
  description = "Project name, used for tagging and resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the ECS service and ALB run in"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the ECS/Fargate tasks"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID for the ECS tasks"
  type        = string
}

variable "container_image" {
  description = "Docker image for the application container (e.g. nginx:latest or a placeholder backend)"
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
}

variable "container_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, ...). Smaller for dev, bigger for prod."
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task memory in MB. Smaller for dev, bigger for prod."
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Number of running tasks. Usually 1 for dev, 2+ for prod (high availability)."
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "Environment variables passed to the container, e.g. DB connection details"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
