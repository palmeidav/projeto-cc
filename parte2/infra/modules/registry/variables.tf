variable "name" { type = string }
variable "services" {
  description = "mapa servico -> diretorio do codigo-fonte (com Dockerfile)"
  type        = map(string)
}
variable "platform" {
  type    = string
  default = "linux/amd64"
}
variable "force_delete" {
  type    = bool
  default = true
}
