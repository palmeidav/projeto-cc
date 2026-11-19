variable "region" {
  description = "Regiao do deploy. Nada no codigo depende de uma regiao especifica."
  type        = string
  default     = "sa-east-1"
}
variable "project" {
  type    = string
  default = "cc"
}
variable "env" {
  description = "Sufixo do ambiente; entra nos nomes (IAM e global, evita colisao com a Parte 1)."
  type        = string
  default     = "sp"
}
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "single_nat_gateway" {
  type    = bool
  default = true
}
variable "alarm_email" {
  type    = string
  default = ""
}

# Bedrock
variable "bedrock_model_id" {
  description = "ID do modelo ou perfil de inferencia disponivel na regiao (ver Fase 0)."
  type        = string
}
variable "llm_mode" {
  description = "bedrock (real) ou mock (testes de carga sem IA)"
  type        = string
  default     = "bedrock"
  validation {
    condition     = contains(["bedrock", "mock"], var.llm_mode)
    error_message = "llm_mode deve ser bedrock ou mock."
  }
}

# Computacao
variable "instance_type" {
  type    = string
  default = "t3.medium"
}
variable "asg_min" {
  type    = number
  default = 2
}
variable "asg_max" {
  type    = number
  default = 4
}
variable "cp_target_capacity" {
  type    = number
  default = 80
}

# Banco
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "db_engine_version" {
  type    = string
  default = null
}
variable "db_multi_az" {
  type    = bool
  default = true
}
variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}
variable "db_deletion_protection" {
  type    = bool
  default = false
}

# Escala dos servicos
variable "chat_target_requests_per_task" {
  description = "Alvo do target tracking do chat (req/min por task). Parte 1: 50 era baixo demais."
  type        = number
  default     = 600
}
variable "rds_connections_threshold" {
  type    = number
  default = 60
}
