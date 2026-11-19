output "alarm_names" { value = sort([for a in aws_cloudwatch_metric_alarm.this : a.alarm_name]) }
output "dashboards" { value = [aws_cloudwatch_dashboard.main.dashboard_name, aws_cloudwatch_dashboard.diag.dashboard_name] }
