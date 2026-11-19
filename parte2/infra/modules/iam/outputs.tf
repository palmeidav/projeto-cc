output "instance_profile_name" { value = aws_iam_instance_profile.instance.name }
output "task_exec_role_arn" { value = aws_iam_role.task_exec.arn }
output "chat_task_role_arn" { value = aws_iam_role.chat.arn }
output "catalog_task_role_arn" { value = aws_iam_role.catalog.arn }
output "worker_task_role_arn" { value = aws_iam_role.worker.arn }
