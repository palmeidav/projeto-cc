# Modulo generico de servico ECS (EC2, modo bridge): log group + task definition + service + autoscaling.
data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name              = "${var.log_group_prefix}/${var.service_name}"
  retention_in_days = var.log_retention_days
}

locals {
  container = merge(
    {
      name              = var.service_name
      image             = var.image
      essential         = true
      cpu               = var.cpu
      memory            = var.memory
      memoryReservation = var.memory_reservation
      portMappings      = var.container_port == null ? [] : [{ containerPort = var.container_port, hostPort = 0, protocol = "tcp" }]
      environment       = [for k in sort(keys(var.environment)) : { name = k, value = var.environment[k] }]
      secrets           = [for k in sort(keys(var.secrets)) : { name = k, valueFrom = var.secrets[k] }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = var.log_stream_prefix
        }
      }
    },
    var.health_check == null ? {} : { healthCheck = var.health_check }
  )
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.family
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions    = jsonencode([local.container])
}

resource "aws_ecs_service" "this" {
  name                               = var.service_name
  cluster                            = var.cluster_name
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = var.target_group_arn == null ? null : 60
  propagate_tags                     = "SERVICE"
  enable_ecs_managed_tags            = true
  enable_execute_command             = false
  availability_zone_rebalancing      = "ENABLED"

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider_name
    weight            = 1
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  lifecycle {
    ignore_changes = [desired_count] # quem manda depois do deploy e o autoscaling
  }
}

# ---------- autoscaling (target tracking) ----------
resource "aws_appautoscaling_target" "this" {
  count              = var.autoscaling == null ? 0 : 1
  service_namespace  = "ecs"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling.min
  max_capacity       = var.autoscaling.max
}

resource "aws_appautoscaling_policy" "this" {
  count              = var.autoscaling == null ? 0 : 1
  name               = var.autoscaling.policy_name
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling.target_value
    scale_out_cooldown = var.autoscaling.scale_out_cooldown
    scale_in_cooldown  = var.autoscaling.scale_in_cooldown

    dynamic "predefined_metric_specification" {
      for_each = var.autoscaling.predefined_metric_type == null ? [] : [1]
      content {
        predefined_metric_type = var.autoscaling.predefined_metric_type
        resource_label         = var.autoscaling.resource_label
      }
    }

    # metrica composta (ex.: backlog da fila por task do worker)
    dynamic "customized_metric_specification" {
      for_each = var.autoscaling.custom_metrics == null ? [] : [1]
      content {
        dynamic "metrics" {
          for_each = var.autoscaling.custom_metrics
          content {
            id          = metrics.value.id
            label       = metrics.value.label
            expression  = metrics.value.expression
            return_data = metrics.value.return_data
            dynamic "metric_stat" {
              for_each = metrics.value.metric == null ? [] : [metrics.value.metric]
              content {
                stat = metric_stat.value.stat
                metric {
                  namespace   = metric_stat.value.namespace
                  metric_name = metric_stat.value.metric_name
                  dynamic "dimensions" {
                    for_each = metric_stat.value.dimensions
                    content {
                      name  = dimensions.key
                      value = dimensions.value
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
