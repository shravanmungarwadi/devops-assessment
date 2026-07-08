project     = "hotelbook"
environment = "dev"
aws_region  = "ap-south-1"

azs                  = ["ap-south-1a", "ap-south-1b"]
vpc_cidr             = "10.10.0.0/16"
public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]

# --- Database: dev sizing ---
db_engine                = "postgres"
db_engine_version        = "16.4"
db_instance_class        = "db.t4g.micro" # small/cheap
db_allocated_storage     = 20
db_name                  = "hotelbook"
db_username              = "app_admin"
db_port                  = 5432
db_backup_retention_days = 1     # short retention, dev data is disposable
db_deletion_protection   = false # ok to tear down freely in dev
db_multi_az              = false # no standby needed in dev

# --- App: dev sizing ---
container_image = "public.ecr.aws/nginx/nginx:latest"
container_port  = 80
task_cpu        = "256"
task_memory     = "512"
desired_count   = 1
