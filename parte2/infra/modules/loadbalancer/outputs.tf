output "alb_dns" { value = aws_lb.this["alb"].dns_name }
output "ilb_dns" { value = aws_lb.this["ilb"].dns_name }
output "alb_arn_suffix" { value = aws_lb.this["alb"].arn_suffix }
output "ilb_arn_suffix" { value = aws_lb.this["ilb"].arn_suffix }
# os TGs so servem para o ECS depois que o listener os associa ao balanceador
output "chat_tg_arn" {
  value      = aws_lb_target_group.this["alb"].arn
  depends_on = [aws_lb_listener.this]
}
output "catalog_tg_arn" {
  value      = aws_lb_target_group.this["ilb"].arn
  depends_on = [aws_lb_listener.this]
}
output "chat_tg_arn_suffix" { value = aws_lb_target_group.this["alb"].arn_suffix }
output "catalog_tg_arn_suffix" { value = aws_lb_target_group.this["ilb"].arn_suffix }
