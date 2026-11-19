variable "name" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "app_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "ilb_sg_id" { type = string }
variable "chat_port" {
  type    = number
  default = 8000
}
variable "catalog_port" {
  type    = number
  default = 8001
}
