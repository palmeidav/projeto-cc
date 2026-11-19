output "alb_sg_id" { value = aws_security_group.this["alb"].id }
output "ilb_sg_id" { value = aws_security_group.this["ilb"].id }
output "app_sg_id" { value = aws_security_group.this["app"].id }
output "db_sg_id" { value = aws_security_group.this["db"].id }
