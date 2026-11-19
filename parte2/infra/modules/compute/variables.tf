variable "name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }
variable "instance_profile_name" { type = string }
variable "instance_type" {
  type    = string
  default = "t3.medium"
}
variable "min_size" {
  type    = number
  default = 2
}
variable "max_size" {
  type    = number
  default = 4
}
variable "cp_target_capacity" {
  description = "Meta de ocupacao do capacity provider (%). 100 = sem instancia ociosa de reserva."
  type        = number
  default     = 80
}
variable "tags" {
  description = "Tags propagadas para instancias e volumes (default_tags nao chega neles)"
  type        = map(string)
  default     = {}
}
