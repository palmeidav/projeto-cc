output "queue_url" { value = aws_sqs_queue.orders.url }
output "queue_arn" { value = aws_sqs_queue.orders.arn }
output "queue_name" { value = aws_sqs_queue.orders.name }
output "dlq_url" { value = aws_sqs_queue.dlq.url }
output "dlq_name" { value = aws_sqs_queue.dlq.name }
output "order_events_topic_arn" { value = aws_sns_topic.order_events.arn }
output "alarms_topic_arn" { value = aws_sns_topic.alarms.arn }
