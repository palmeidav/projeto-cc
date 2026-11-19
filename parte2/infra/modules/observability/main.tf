data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
  ns_app = "CC" # namespace das metricas EMF publicadas pelo codigo
}

# Metrica de erros a partir dos logs JSON (nos 3 grupos)
resource "aws_cloudwatch_log_metric_filter" "errors" {
  for_each       = var.log_group_names
  name           = "errors"
  log_group_name = each.value
  pattern        = "{ $.level = \"ERROR\" }"
  metric_transformation {
    name      = "AppErrors"
    namespace = local.ns_app
    value     = "1"
  }
}

locals {
  alb_dims     = { LoadBalancer = var.alb_arn_suffix }
  cluster_dims = { ClusterName = var.cluster_name }
  db_dims      = { DBInstanceIdentifier = var.db_identifier }

  alarms = merge(
    {
      unhealthy = {
        namespace = "AWS/ApplicationELB", metric = "UnHealthyHostCount", stat = "Maximum", op = "GreaterThanThreshold", threshold = 0
        dims      = merge(local.alb_dims, { TargetGroup = var.chat_tg_arn_suffix })
      }
      "5xx" = {
        namespace = "AWS/ApplicationELB", metric = "HTTPCode_Target_5XX_Count", stat = "Sum", op = "GreaterThanThreshold", threshold = 5
        dims      = local.alb_dims
      }
      latency-p95 = {
        namespace = "AWS/ApplicationELB", metric = "TargetResponseTime", extended = "p95", op = "GreaterThanThreshold", threshold = 5
        dims      = local.alb_dims
      }
      dlq-not-empty = {
        namespace = "AWS/SQS", metric = "ApproximateNumberOfMessagesVisible", stat = "Maximum", op = "GreaterThanThreshold", threshold = 0
        dims      = { QueueName = var.dlq_name }
      }
      queue-age = {
        namespace = "AWS/SQS", metric = "ApproximateAgeOfOldestMessage", stat = "Maximum", op = "GreaterThanThreshold", threshold = 120
        dims      = { QueueName = var.queue_name }
      }
      asg-capacity = {
        namespace = "AWS/AutoScaling", metric = "GroupInServiceInstances", stat = "Minimum", op = "LessThanThreshold", threshold = var.asg_min_size
        dims      = { AutoScalingGroupName = var.asg_name }
      }
      cluster-cpu = {
        namespace = "AWS/ECS", metric = "CPUReservation", stat = "Average", op = "GreaterThanThreshold", threshold = 85
        dims      = local.cluster_dims
      }
      cluster-mem = {
        namespace = "AWS/ECS", metric = "MemoryReservation", stat = "Average", op = "GreaterThanThreshold", threshold = 85
        dims      = local.cluster_dims
      }
      rds-cpu = {
        namespace = "AWS/RDS", metric = "CPUUtilization", stat = "Average", op = "GreaterThanThreshold", threshold = 80
        dims      = local.db_dims
      }
      # licao da Parte 1: 80 so disparava com o banco ja esgotado
      rds-connections = {
        namespace = "AWS/RDS", metric = "DatabaseConnections", stat = "Maximum", op = "GreaterThanThreshold", threshold = var.rds_connections_threshold
        dims      = local.db_dims
      }
      app-errors = {
        namespace = local.ns_app, metric = "AppErrors", stat = "Sum", op = "GreaterThanThreshold", threshold = 3, periods = 1
        dims      = {}
      }
    },
    { for s in var.service_names : "tasks-${s}" => {
      namespace = "ECS/ContainerInsights", metric = "RunningTaskCount", stat = "Minimum", op = "LessThanThreshold", threshold = 1
      dims      = merge(local.cluster_dims, { ServiceName = s })
    } }
  )
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${var.name}-${each.key}"
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  statistic           = try(each.value.extended, null) == null ? each.value.stat : null
  extended_statistic  = try(each.value.extended, null)
  comparison_operator = each.value.op
  threshold           = each.value.threshold
  period              = 60
  evaluation_periods  = try(each.value.periods, 2)
  treat_missing_data  = "notBreaching"
  dimensions          = each.value.dims
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
}

# ---------- dashboards ----------
locals {
  w   = { region = local.region, view = "timeSeries", period = 60 }
  svc = var.service_names

  dashboard_main = { widgets = [
    { type = "metric", x = 0, y = 0, width = 8, height = 6, properties = merge(local.w, {
      title = "ALB: requisicoes e 5xx", stat = "Sum",
      metrics = [
        ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
        [".", "HTTPCode_Target_5XX_Count", ".", "."],
        [".", "HTTPCode_ELB_5XX_Count", ".", "."],
    ] }) },
    { type = "metric", x = 8, y = 0, width = 8, height = 6, properties = merge(local.w, {
      title   = "ALB: latencia p95 (s)", stat = "p95",
      metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95" }]]
    }) },
    { type = "metric", x = 16, y = 0, width = 8, height = 6, properties = merge(local.w, {
      title = "Tasks em execucao por servico", stat = "Average",
      metrics = concat(
        [for s in local.svc : ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", s]],
        [["ECS/ContainerInsights", "PendingTaskCount", "ClusterName", var.cluster_name, "ServiceName", local.svc[0]]]
      )
    }) },
    { type = "metric", x = 0, y = 6, width = 8, height = 6, properties = merge(local.w, {
      title = "Cluster: CPU/memoria reservada (%) e CapacityProviderReservation", stat = "Average",
      metrics = [
        ["AWS/ECS", "CPUReservation", "ClusterName", var.cluster_name],
        [".", "MemoryReservation", ".", "."],
        ["AWS/ECS/ManagedScaling", "CapacityProviderReservation", "ClusterName", var.cluster_name, "CapacityProviderName", var.capacity_provider_name],
    ] }) },
    { type = "metric", x = 8, y = 6, width = 8, height = 6, properties = merge(local.w, {
      title = "ASG: instancias", stat = "Maximum",
      metrics = [
        ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name],
        [".", "GroupDesiredCapacity", ".", "."],
        [".", "GroupPendingInstances", ".", "."],
    ] }) },
    { type = "metric", x = 16, y = 6, width = 8, height = 6, properties = merge(local.w, {
      title = "Fila e DLQ (mensagens visiveis)", stat = "Maximum",
      metrics = [
        ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.queue_name],
        ["...", var.dlq_name],
    ] }) },
    { type = "metric", x = 0, y = 12, width = 8, height = 6, properties = merge(local.w, {
      title = "RDS: CPU (%) e conexoes", stat = "Average",
      metrics = [
        ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier],
        [".", "DatabaseConnections", ".", ".", { yAxis = "right" }],
    ] }) },
    { type = "metric", x = 8, y = 12, width = 8, height = 6, properties = merge(local.w, {
      title   = "AppErrors (CC)", stat = "Sum",
      metrics = [[local.ns_app, "AppErrors"], [".", "ChatDegraded"], [".", "OrderProcessingFailures"]]
    }) },
    { type = "metric", x = 16, y = 12, width = 8, height = 6, properties = merge(local.w, {
      title   = "Negocio: OrdersCreated / OrdersConfirmed / OutboxPending", stat = "Sum",
      metrics = [[local.ns_app, "OrdersCreated"], [".", "OrdersConfirmed"], [".", "OutboxPending", { stat = "Maximum" }]]
    }) },
    { type = "metric", x = 0, y = 18, width = 8, height = 6, properties = merge(local.w, {
      title   = "LLMLatencyMs (Bedrock)", stat = "Average",
      metrics = [[local.ns_app, "LLMLatencyMs", { stat = "Average" }], ["...", { stat = "p95" }]]
    }) },
  ] }

  logs_source = join(" | ", [for g in values(var.log_group_names) : "SOURCE '${g}'"])

  dashboard_diag = { widgets = [
    { type = "alarm", x = 0, y = 0, width = 8, height = 4, properties = {
      title  = "1) Alarmes"
      alarms = [for k in ["app-errors", "5xx", "unhealthy", "dlq-not-empty"] : aws_cloudwatch_metric_alarm.this[k].arn]
    } },
    { type = "metric", x = 8, y = 0, width = 8, height = 4, properties = merge(local.w, {
      title   = "2) Erros da aplicacao: AppErrors e ChatDegraded", stat = "Sum",
      metrics = [[local.ns_app, "AppErrors"], [".", "ChatDegraded"]]
    }) },
    { type = "metric", x = 16, y = 0, width = 8, height = 4, properties = merge(local.w, {
      title   = "2) Bedrock: LLMLatencyMs (sem dados = nenhuma chamada OK)", stat = "SampleCount",
      metrics = [[local.ns_app, "LLMLatencyMs"]]
    }) },
    { type = "metric", x = 0, y = 4, width = 12, height = 4, properties = merge(local.w, {
      title = "2) Infra: ALB 5xx e requisicoes", stat = "Sum",
      metrics = [
        ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
        ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
    ] }) },
    { type = "metric", x = 12, y = 4, width = 12, height = 4, properties = merge(local.w, {
      title   = "2) Tasks em execucao", stat = "Minimum",
      metrics = [for s in local.svc : ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", s]]
    }) },
    { type = "log", x = 0, y = 8, width = 24, height = 6, properties = {
      title  = "3) Erros recentes nos 3 servicos (Logs Insights)"
      region = local.region
      view   = "table"
      query  = "${local.logs_source} | fields @timestamp, service, level, message, conversation_id, order_id, erro | filter level = 'ERROR' | sort @timestamp desc | limit 50"
    } },
  ] }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.name
  dashboard_body = jsonencode(local.dashboard_main)
}

resource "aws_cloudwatch_dashboard" "diag" {
  dashboard_name = "${var.name}-diagnostico"
  dashboard_body = jsonencode(local.dashboard_diag)
}
