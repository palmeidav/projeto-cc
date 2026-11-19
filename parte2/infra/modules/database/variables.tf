variable "name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "engine_version" {
  description = "Versao do Postgres; null = padrao da regiao."
  type        = string
  default     = null
}
variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "allocated_storage" {
  type    = number
  default = 20
}
variable "db_name" {
  type    = string
  default = "shop"
}
variable "username" {
  type    = string
  default = "cc_admin"
}
variable "multi_az" {
  type    = bool
  default = true
}
variable "backup_retention_days" {
  type    = number
  default = 1
}
variable "skip_final_snapshot" {
  type    = bool
  default = true
}
variable "deletion_protection" {
  type    = bool
  default = false
}
