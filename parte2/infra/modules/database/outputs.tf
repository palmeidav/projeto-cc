output "address" { value = aws_db_instance.this.address }
output "identifier" { value = aws_db_instance.this.identifier }
output "db_name" { value = aws_db_instance.this.db_name }
output "username" { value = aws_db_instance.this.username }
output "secret_arn" {
  description = "ARN do segredo gerenciado pelo RDS (so o ARN, nunca o valor)"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
