resource "aws_security_group" "this" {
  for_each    = toset(["alb", "ilb", "app", "db"])
  name        = "${var.name}-${each.key}"
  description = "${var.name}-${each.key}"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-${each.key}" }
}

# Saida liberada (o Terraform remove a regra padrao da AWS)
resource "aws_vpc_security_group_egress_rule" "all" {
  for_each          = aws_security_group.this
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.this["alb"].id
  description       = "HTTP publico"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.alb_ingress_cidr
}

resource "aws_vpc_security_group_ingress_rule" "ilb_from_app" {
  security_group_id            = aws_security_group.this["ilb"].id
  description                  = "chat -> ALB interno"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.this["app"].id
}

# Portas dinamicas do modo bridge
resource "aws_vpc_security_group_ingress_rule" "app_from_lb" {
  for_each                     = toset(["alb", "ilb"])
  security_group_id            = aws_security_group.this["app"].id
  description                  = "portas dinamicas a partir do ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = 32768
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.this[each.key].id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.this["db"].id
  description                  = "Postgres a partir das tasks"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.this["app"].id
}
