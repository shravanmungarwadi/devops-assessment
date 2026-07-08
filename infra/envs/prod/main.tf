module "network" {
  source = "../../modules/network"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  container_port       = var.container_port
  db_port              = var.db_port
}

module "rds" {
  source = "../../modules/rds"

  project                 = var.project
  environment             = var.environment
  engine                  = var.db_engine
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  port                    = var.db_port
  private_subnet_ids      = module.network.private_subnet_ids
  vpc_security_group_ids  = [module.network.rds_security_group_id]
  backup_retention_period = var.db_backup_retention_days
  deletion_protection     = var.db_deletion_protection
  multi_az                = var.db_multi_az
  skip_final_snapshot     = false # prod: always take a final snapshot on destroy
}

module "ecs" {
  source = "../../modules/ecs"

  project               = var.project
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  ecs_security_group_id = module.network.ecs_security_group_id
  container_image       = var.container_image
  container_port        = var.container_port
  task_cpu              = var.task_cpu
  task_memory           = var.task_memory
  desired_count         = var.desired_count

  environment_variables = {
    DB_HOST = module.rds.db_address
    DB_PORT = tostring(module.rds.db_port)
    DB_NAME = module.rds.db_name
  }
}
