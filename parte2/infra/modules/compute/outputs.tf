# Saida a partir do recurso de associacao: quem usa o cluster espera o capacity provider existir
output "cluster_name" { value = aws_ecs_cluster_capacity_providers.this.cluster_name }
output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "capacity_provider_name" { value = aws_ecs_capacity_provider.this.name }
output "asg_name" { value = aws_autoscaling_group.this.name }
