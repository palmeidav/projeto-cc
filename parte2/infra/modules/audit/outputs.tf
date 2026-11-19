output "trail_name" { value = aws_cloudtrail.this.name }
output "trail_bucket" { value = aws_s3_bucket.trail.bucket }
output "trail_log_group" { value = aws_cloudwatch_log_group.trail.name }
output "alarm_names" { value = sort([for a in aws_cloudwatch_metric_alarm.audit : a.alarm_name]) }
