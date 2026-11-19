# Estado remoto em S3 com lock nativo. Configuracao parcial: os valores vem de backend.hcl
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
