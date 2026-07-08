locals {
  name_prefix = "${var.project}-${var.environment}"

  # Map our simplified "postgres"/"mysql" choice to the real RDS engine identifier.
  engine_map = {
    postgres = "postgres"
    mysql    = "mysql"
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name_prefix}-db"
  engine         = local.engine_map[var.engine]
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.vpc_security_group_ids

  # RDS is placed in private subnets only and is never given a public IP,
  # so it is unreachable from the internet regardless of security group
  # rules. The security group additionally restricts access to the ECS SG.
  publicly_accessible = false

  backup_retention_period   = var.backup_retention_period
  multi_az                  = var.multi_az
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-final-snapshot"

  apply_immediately = var.environment != "prod"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-db"
  })
}
