variable "service_name" { type = string }
variable "family" { type = string }
variable "image" { type = string }
variable "cluster_name" { type = string }
variable "capacity_provider_name" { type = string }
variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "cpu" { type = number }
variable "memory" { type = number }
variable "memory_reservation" { type = number }
variable "desired_count" { type = number }
variable "container_port" {
  type    = number
  default = null
}
variable "target_group_arn" {
  type    = string
  default = null
}
variable "environment" {
  type    = map(string)
  default = {}
}
variable "secrets" {
  description = "nome da variavel -> ARN (valueFrom). So ARNs, nunca valores."
  type        = map(string)
  default     = {}
}
variable "health_check" {
  type    = any
  default = null
}
variable "placement_strategy" {
  type = list(object({ type = string, field = string }))
  default = [
    { type = "spread", field = "attribute:ecs.availability-zone" },
    { type = "spread", field = "instanceId" },
  ]
}
variable "log_group_prefix" { type = string }
variable "log_stream_prefix" { type = string }
variable "log_retention_days" {
  type    = number
  default = 7
}
variable "autoscaling" {
  type = object({
    min                    = number
    max                    = number
    policy_name            = string
    target_value           = number
    scale_out_cooldown     = optional(number, 60)
    scale_in_cooldown      = optional(number, 120)
    predefined_metric_type = optional(string)
    resource_label         = optional(string)
    custom_metrics = optional(list(object({
      id          = string
      label       = optional(string)
      expression  = optional(string)
      return_data = optional(bool, false)
      metric = optional(object({
        namespace   = string
        metric_name = string
        stat        = string
        dimensions  = map(string)
      }))
    })))
  })
  default = null
}
