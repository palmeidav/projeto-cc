# IAM e global: o prefixo (ex.: cc-sp) evita colisao com os papeis da Parte 1 na mesma conta
data "aws_caller_identity" "me" {}
data "aws_region" "current" {}
data "aws_partition" "p" {}

locals {
  region  = data.aws_region.current.region
  account = data.aws_caller_identity.me.account_id
  # "us.anthropic.x" / "global.anthropic.x" -> "anthropic.x"
  bedrock_base_model = replace(var.bedrock_model_id, "/^(us|eu|apac|global|sa|ca|jp|au|us-gov)\\./", "")
}

data "aws_iam_policy_document" "trust_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "trust_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

# 1) Instancias EC2 do cluster
resource "aws_iam_role" "instance" {
  name               = "${var.name}-ecs-instance-role"
  assume_role_policy = data.aws_iam_policy_document.trust_ec2.json
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each = toset([
    "arn:${data.aws_partition.p.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:${data.aws_partition.p.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-ecs-instance-profile"
  role = aws_iam_role.instance.name
}

# 2) Execucao das tasks (pull do ECR, logs, segredo do banco)
resource "aws_iam_role" "task_exec" {
  name               = "${var.name}-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.trust_ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "task_exec" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:${data.aws_partition.p.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_exec" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "task_exec" {
  name   = "db-secret"
  role   = aws_iam_role.task_exec.id
  policy = data.aws_iam_policy_document.task_exec.json
}

# 3) chat-service: so o modelo configurado (licao da Parte 1: antes era Resource "*")
resource "aws_iam_role" "chat" {
  name               = "${var.name}-chat-task-role"
  assume_role_policy = data.aws_iam_policy_document.trust_ecs_tasks.json
}

data "aws_iam_policy_document" "chat" {
  statement {
    sid     = "InvokeConfiguredModel"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      # perfil de inferencia na regiao do deploy
      "arn:${data.aws_partition.p.partition}:bedrock:${local.region}:${local.account}:inference-profile/${var.bedrock_model_id}",
      # o perfil roteia para o modelo base em outras regioes (o * cobre tambem o ARN sem regiao do perfil global)
      "arn:${data.aws_partition.p.partition}:bedrock:*::foundation-model/${local.bedrock_base_model}",
    ]
  }
}

resource "aws_iam_role_policy" "chat" {
  name   = "bedrock-model"
  role   = aws_iam_role.chat.id
  policy = data.aws_iam_policy_document.chat.json
}

# 4) catalog-orders-service: publica na fila
resource "aws_iam_role" "catalog" {
  name               = "${var.name}-catalog-task-role"
  assume_role_policy = data.aws_iam_policy_document.trust_ecs_tasks.json
}

data "aws_iam_policy_document" "catalog" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [var.queue_arn]
  }
}

resource "aws_iam_role_policy" "catalog" {
  name   = "sqs-send"
  role   = aws_iam_role.catalog.id
  policy = data.aws_iam_policy_document.catalog.json
}

# 5) order-worker: consome a fila e publica o evento
resource "aws_iam_role" "worker" {
  name               = "${var.name}-worker-task-role"
  assume_role_policy = data.aws_iam_policy_document.trust_ecs_tasks.json
}

data "aws_iam_policy_document" "worker" {
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
    resources = [var.queue_arn]
  }
  statement {
    actions   = ["sns:Publish"]
    resources = [var.order_events_topic_arn]
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "sqs-consume-sns-publish"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}
