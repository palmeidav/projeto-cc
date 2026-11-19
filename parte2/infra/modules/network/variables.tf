variable "name" { type = string }
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "az_count" {
  type    = number
  default = 2
  validation {
    condition     = var.az_count >= 2
    error_message = "Alta disponibilidade exige pelo menos 2 AZs."
  }
}
variable "single_nat_gateway" {
  type    = bool
  default = true
}
