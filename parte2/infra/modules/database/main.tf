resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db-subnets"
  description = "${var.name} data subnets"
  subnet_ids  = var.subnet_ids
}

# Senha gerada e guardada pelo RDS no Secrets Manager: nunca passa pelo Terraform nem pelo estado
resource "aws_db_instance" "this" {
  identifier                  = "${var.name}-db"
  engine                      = "postgres"
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.db_name
  username                    = var.username
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [var.security_group_id]
  multi_az                    = var.multi_az
  publicly_accessible         = false
  backup_retention_period     = var.backup_retention_days
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.skip_final_snapshot ? null : "${var.name}-db-final"
  deletion_protection         = var.deletion_protection
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  copy_tags_to_snapshot       = true
}
