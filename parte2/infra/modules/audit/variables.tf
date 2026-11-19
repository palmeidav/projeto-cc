variable "name" { type = string }
variable "alarm_topic_arn" { type = string }
variable "log_group_prefix" { type = string }
variable "force_destroy" {
  description = "Permite destruir o bucket com logs dentro (destroy reproduzivel no laboratorio)."
  type        = bool
  default     = true
}
variable "s3_retention_days" {
  type    = number
  default = 90
}
variable "cwl_retention_days" {
  type    = number
  default = 30
}
