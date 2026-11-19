locals {
  lbs = {
    alb = { internal = false, subnets = var.public_subnet_ids, sg = var.alb_sg_id, port = var.chat_port, tg = "chat" }
    ilb = { internal = true, subnets = var.app_subnet_ids, sg = var.ilb_sg_id, port = var.catalog_port, tg = "catalog" }
  }
}

resource "aws_lb" "this" {
  for_each                   = local.lbs
  name                       = "${var.name}-${each.key}"
  internal                   = each.value.internal
  load_balancer_type         = "application"
  subnets                    = each.value.subnets
  security_groups            = [each.value.sg]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "this" {
  for_each             = local.lbs
  name                 = "${var.name}-tg-${each.value.tg}"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = var.vpc_id
  deregistration_delay = 30
  health_check {
    path                = "/health"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

resource "aws_lb_listener" "this" {
  for_each          = local.lbs
  load_balancer_arn = aws_lb.this[each.key].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}
