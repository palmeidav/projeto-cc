resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# AMI otimizada para ECS da regiao do deploy (nenhum ID fixo)
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

locals {
  instance_tags = merge(var.tags, { Name = "${var.name}-ecs" })
}

resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-lt-"
  image_id               = data.aws_ssm_parameter.ecs_ami.insecure_value
  instance_type          = var.instance_type
  vpc_security_group_ids = [var.security_group_id]
  update_default_version = true
  user_data = base64encode(templatefile("${path.module}/userdata.sh.tftpl", {
    cluster_name = aws_ecs_cluster.this.name
  }))

  iam_instance_profile { name = var.instance_profile_name }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  monitoring { enabled = true }

  # licao da Parte 1: volumes sem tag. Aqui instancia E volume nascem com tag.
  tag_specifications {
    resource_type = "instance"
    tags          = local.instance_tags
  }
  tag_specifications {
    resource_type = "volume"
    tags          = local.instance_tags
  }
  tag_specifications {
    resource_type = "network-interface"
    tags          = local.instance_tags
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = "${var.name}-asg"
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.min_size
  vpc_zone_identifier       = var.subnet_ids
  health_check_type         = "EC2"
  health_check_grace_period = 120
  protect_from_scale_in     = true # exigido pela protecao gerenciada do capacity provider
  force_delete              = true # permite destroy reproduzivel
  enabled_metrics = [
    "GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances",
    "GroupPendingInstances", "GroupTerminatingInstances", "GroupTotalInstances",
  ]

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage       = 50
      scale_in_protected_instances = "Refresh"
    }
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.instance_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    # o capacity provider controla a capacidade desejada
    ignore_changes = [desired_capacity]
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name}-cp"
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.this.arn
    managed_termination_protection = "ENABLED"
    managed_draining               = "ENABLED"
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = var.cp_target_capacity
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }
}
