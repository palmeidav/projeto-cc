locals {
  name = "${var.project}-${var.env}"
  tags = { project = var.project, env = var.env, managed-by = "terraform" }

  services_dir = abspath("${path.root}/../../../services")
  sources = {
    chat-service           = "${local.services_dir}/chat-service"
    catalog-orders-service = "${local.services_dir}/catalog-orders-service"
    order-worker           = "${local.services_dir}/order-worker"
  }
  log_prefix = "/${var.project}/${var.env}"
}

module "network" {
  source             = "../../modules/network"
  name               = local.name
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "security" {
  source = "../../modules/security"
  name   = local.name
  vpc_id = module.network.vpc_id
}

module "database" {
  source              = "../../modules/database"
  name                = local.name
  subnet_ids          = module.network.data_subnet_ids
  security_group_id   = module.security.db_sg_id
  instance_class      = var.db_instance_class
  engine_version      = var.db_engine_version
  multi_az            = var.db_multi_az
  skip_final_snapshot = var.db_skip_final_snapshot
  deletion_protection = var.db_deletion_protection
}

module "messaging" {
  source      = "../../modules/messaging"
  name        = local.name
  alarm_email = var.alarm_email
}

module "iam" {
  source                 = "../../modules/iam"
  name                   = local.name
  db_secret_arn          = module.database.secret_arn
  queue_arn              = module.messaging.queue_arn
  order_events_topic_arn = module.messaging.order_events_topic_arn
  bedrock_model_id       = var.bedrock_model_id
}

module "registry" {
  source   = "../../modules/registry"
  name     = local.name
  services = local.sources
}

module "compute" {
  source                = "../../modules/compute"
  name                  = local.name
  subnet_ids            = module.network.app_subnet_ids
  security_group_id     = module.security.app_sg_id
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  min_size              = var.asg_min
  max_size              = var.asg_max
  cp_target_capacity    = var.cp_target_capacity
  tags                  = local.tags
}

module "loadbalancer" {
  source            = "../../modules/loadbalancer"
  name              = local.name
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  app_subnet_ids    = module.network.app_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  ilb_sg_id         = module.security.ilb_sg_id
}

locals {
  db_env = {
    AWS_REGION = var.region
    DB_HOST    = module.database.address
    DB_NAME    = module.database.db_name
    DB_USER    = module.database.username
  }
  db_secrets = { DB_PASSWORD = "${module.database.secret_arn}:password::" }

  common = {
    cluster_name           = module.compute.cluster_name
    capacity_provider_name = module.compute.capacity_provider_name
    execution_role_arn     = module.iam.task_exec_role_arn
    log_group_prefix       = local.log_prefix
  }
}

module "catalog" {
  source                 = "../../modules/service"
  service_name           = "catalog-orders-service"
  family                 = "${local.name}-catalog"
  image                  = module.registry.images["catalog-orders-service"]
  cluster_name           = local.common.cluster_name
  capacity_provider_name = local.common.capacity_provider_name
  execution_role_arn     = local.common.execution_role_arn
  task_role_arn          = module.iam.catalog_task_role_arn
  log_group_prefix       = local.common.log_group_prefix
  log_stream_prefix      = "catalog"
  cpu                    = 256
  memory                 = 512
  memory_reservation     = 256
  desired_count          = 2
  container_port         = 8001
  target_group_arn       = module.loadbalancer.catalog_tg_arn
  environment            = merge(local.db_env, { QUEUE_URL = module.messaging.queue_url })
  secrets                = local.db_secrets
  health_check = {
    command  = ["CMD-SHELL", "curl -f http://localhost:8001/health || exit 1"]
    interval = 15, timeout = 5, retries = 3, startPeriod = 30
  }
  autoscaling = {
    min                    = 2, max = 6, policy_name = "catalog-cpu", target_value = 60
    predefined_metric_type = "ECSServiceAverageCPUUtilization"
  }
}

module "chat" {
  source                 = "../../modules/service"
  service_name           = "chat-service"
  family                 = "${local.name}-chat"
  image                  = module.registry.images["chat-service"]
  cluster_name           = local.common.cluster_name
  capacity_provider_name = local.common.capacity_provider_name
  execution_role_arn     = local.common.execution_role_arn
  task_role_arn          = module.iam.chat_task_role_arn
  log_group_prefix       = local.common.log_group_prefix
  log_stream_prefix      = "chat"
  cpu                    = 512
  memory                 = 1024
  memory_reservation     = 512
  desired_count          = 2
  container_port         = 8000
  target_group_arn       = module.loadbalancer.chat_tg_arn
  environment = merge(local.db_env, {
    CATALOG_URL      = "http://${module.loadbalancer.ilb_dns}"
    BEDROCK_MODEL_ID = var.bedrock_model_id
    LLM_MODE         = var.llm_mode
  })
  secrets = local.db_secrets
  health_check = {
    command  = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
    interval = 15, timeout = 5, retries = 3, startPeriod = 30
  }
  autoscaling = {
    min                    = 2, max = 6, policy_name = "chat-req", target_value = var.chat_target_requests_per_task
    predefined_metric_type = "ALBRequestCountPerTarget"
    resource_label         = "${module.loadbalancer.alb_arn_suffix}/${module.loadbalancer.chat_tg_arn_suffix}"
  }
  depends_on = [module.catalog] # o chat depende do catalog no /ready
}

module "worker" {
  source                 = "../../modules/service"
  service_name           = "order-worker"
  family                 = "${local.name}-worker"
  image                  = module.registry.images["order-worker"]
  cluster_name           = local.common.cluster_name
  capacity_provider_name = local.common.capacity_provider_name
  execution_role_arn     = local.common.execution_role_arn
  task_role_arn          = module.iam.worker_task_role_arn
  log_group_prefix       = local.common.log_group_prefix
  log_stream_prefix      = "worker"
  cpu                    = 256
  memory                 = 512
  memory_reservation     = 256
  desired_count          = 1
  environment = merge(local.db_env, {
    QUEUE_URL = module.messaging.queue_url
    TOPIC_ARN = module.messaging.order_events_topic_arn
  })
  secrets = local.db_secrets
  health_check = {
    command  = ["CMD-SHELL", "test $(( $(date +%s) - $(stat -c %Y /tmp/heartbeat) )) -lt 90"]
    interval = 15, timeout = 5, retries = 3, startPeriod = 30
  }
  placement_strategy = [
    { type = "spread", field = "attribute:ecs.availability-zone" },
    { type = "binpack", field = "memory" },
  ]
  autoscaling = {
    min = 1, max = 5, policy_name = "worker-backlog", target_value = 5, scale_in_cooldown = 180
    custom_metrics = [
      { id = "m1", metric = { namespace = "AWS/SQS", metric_name = "ApproximateNumberOfMessagesVisible", stat = "Average",
      dimensions = { QueueName = module.messaging.queue_name } } },
      { id = "m2", metric = { namespace = "ECS/ContainerInsights", metric_name = "RunningTaskCount", stat = "Average",
      dimensions = { ClusterName = module.compute.cluster_name, ServiceName = "order-worker" } } },
      { id = "e1", expression = "m1/m2", label = "backlog por task", return_data = true },
    ]
  }
}

module "observability" {
  source          = "../../modules/observability"
  name            = local.name
  alarm_topic_arn = module.messaging.alarms_topic_arn
  service_names   = [module.chat.service_name, module.catalog.service_name, module.worker.service_name]
  log_group_names = {
    chat    = module.chat.log_group_name
    catalog = module.catalog.log_group_name
    worker  = module.worker.log_group_name
  }
  alb_arn_suffix            = module.loadbalancer.alb_arn_suffix
  chat_tg_arn_suffix        = module.loadbalancer.chat_tg_arn_suffix
  cluster_name              = module.compute.cluster_name
  capacity_provider_name    = module.compute.capacity_provider_name
  asg_name                  = module.compute.asg_name
  asg_min_size              = var.asg_min
  queue_name                = module.messaging.queue_name
  dlq_name                  = module.messaging.dlq_name
  db_identifier             = module.database.identifier
  rds_connections_threshold = var.rds_connections_threshold
}

module "audit" {
  source           = "../../modules/audit"
  name             = local.name
  alarm_topic_arn  = module.messaging.alarms_topic_arn
  log_group_prefix = local.log_prefix
}
