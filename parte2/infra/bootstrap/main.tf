# Cria o bucket S3 do estado remoto. Estado local; roda uma vez por conta/regiao.
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

variable "region" {
  type    = string
  default = "sa-east-1"
}
variable "project" {
  type    = string
  default = "cc"
}
variable "force_destroy" {
  description = "Permite destruir o bucket mesmo com versoes de estado dentro (laboratorio)."
  type        = bool
  default     = false
}

provider "aws" {
  region = var.region
  default_tags { tags = { project = var.project, managed-by = "terraform" } }
}

data "aws_caller_identity" "me" {}

resource "aws_s3_bucket" "state" {
  bucket        = "${var.project}-tfstate-${data.aws_caller_identity.me.account_id}-${var.region}"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expira-versoes-antigas"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "backend_hcl" {
  description = "Conteudo sugerido para envs/<regiao>/backend.hcl"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    key          = "livraria-nuvem/${var.region}/terraform.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
