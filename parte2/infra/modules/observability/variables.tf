variable "name" { type = string }
variable "alarm_topic_arn" { type = string }
variable "log_group_names" {
  description = "servico -> nome do log group"
  type        = map(string)
}
variable "service_names" { type = list(string) }
variable "alb_arn_suffix" { type = string }
variable "chat_tg_arn_suffix" { type = string }
variable "cluster_name" { type = string }
variable "capacity_provider_name" { type = string }
variable "asg_name" { type = string }
variable "asg_min_size" { type = number }
variable "queue_name" { type = string }
variable "dlq_name" { type = string }
variable "db_identifier" { type = string }
variable "rds_connections_threshold" {
  type    = number
  default = 60
}
