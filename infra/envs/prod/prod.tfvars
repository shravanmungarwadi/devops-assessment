project     = "hotelbook"
environment = "prod"
aws_region  = "ap-south-1"

azs                  = ["ap-south-1a", "ap-south-1b"]
vpc_cidr             = "10.20.0.0/16"
public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]

# --- Database: prod sizing ---
# db_password is intentionally NOT set here - pass it via
# `TF_VAR_db_password` (or wire it to Secrets Manager) so it never lands in
# git history.
db_engine                = "postgres"
db_engine_version        = "16.4"
db_instance_class        = "db.r6g.large" # bigger than dev
db_allocated_storage     = 100
db_name                  = "hotelbook"
db_username              = "app_admin"
db_port                  = 5432
db_backup_retention_days = 30   # longer retention than dev
db_deletion_protection   = true # protected from accidental destroy
db_multi_az              = true # standby replica for HA

# --- App: prod sizing ---
container_image = "public.ecr.aws/nginx/nginx:latest"
container_port  = 80
task_cpu        = "1024"
task_memory     = "2048"
desired_count   = 2
