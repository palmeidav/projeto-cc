variable "name" { type = string }
variable "visibility_timeout" {
  type    = number
  default = 60
}
variable "max_receive_count" {
  type    = number
  default = 3
}
variable "alarm_email" {
  description = "E-mail que recebe os alarmes (vazio = sem assinatura)"
  type        = string
  default     = ""
}
