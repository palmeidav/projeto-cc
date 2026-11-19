variable "name" { type = string }
variable "vpc_id" { type = string }
variable "alb_ingress_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
