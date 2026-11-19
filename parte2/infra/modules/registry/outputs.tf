output "images" {
  description = "servico -> URI completa da imagem publicada (so existe depois do push)"
  value       = { for s, d in terraform_data.image : s => d.output }
}
output "repository_urls" { value = { for s, r in aws_ecr_repository.this : s => r.repository_url } }
