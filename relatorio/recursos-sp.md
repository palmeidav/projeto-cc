# Recursos criados em São Paulo (sa-east-1) pelo Terraform

Gerado do estado remoto (`terraform show -json`). **125 recursos gerenciados** em 13 módulos.

## Resumo por tipo

| Tipo | Qtd |
|---|---|
| `aws_appautoscaling_policy` | 3 |
| `aws_appautoscaling_target` | 3 |
| `aws_autoscaling_group` | 1 |
| `aws_cloudtrail` | 1 |
| `aws_cloudwatch_dashboard` | 2 |
| `aws_cloudwatch_log_group` | 4 |
| `aws_cloudwatch_log_metric_filter` | 6 |
| `aws_cloudwatch_metric_alarm` | 17 |
| `aws_db_instance` | 1 |
| `aws_db_subnet_group` | 1 |
| `aws_ecr_lifecycle_policy` | 3 |
| `aws_ecr_repository` | 3 |
| `aws_ecs_capacity_provider` | 1 |
| `aws_ecs_cluster` | 1 |
| `aws_ecs_cluster_capacity_providers` | 1 |
| `aws_ecs_service` | 3 |
| `aws_ecs_task_definition` | 3 |
| `aws_eip` | 1 |
| `aws_iam_instance_profile` | 1 |
| `aws_iam_role` | 6 |
| `aws_iam_role_policy` | 5 |
| `aws_iam_role_policy_attachment` | 3 |
| `aws_internet_gateway` | 1 |
| `aws_launch_template` | 1 |
| `aws_lb` | 2 |
| `aws_lb_listener` | 2 |
| `aws_lb_target_group` | 2 |
| `aws_nat_gateway` | 1 |
| `aws_route` | 2 |
| `aws_route_table` | 3 |
| `aws_route_table_association` | 6 |
| `aws_s3_bucket` | 1 |
| `aws_s3_bucket_lifecycle_configuration` | 1 |
| `aws_s3_bucket_policy` | 1 |
| `aws_s3_bucket_public_access_block` | 1 |
| `aws_s3_bucket_server_side_encryption_configuration` | 1 |
| `aws_security_group` | 4 |
| `aws_sns_topic` | 2 |
| `aws_sns_topic_subscription` | 1 |
| `aws_sqs_queue` | 2 |
| `aws_sqs_queue_redrive_allow_policy` | 1 |
| `aws_subnet` | 6 |
| `aws_vpc` | 1 |
| `aws_vpc_endpoint` | 1 |
| `aws_vpc_security_group_egress_rule` | 4 |
| `aws_vpc_security_group_ingress_rule` | 5 |
| `terraform_data` | 3 |

## Lista completa

| Módulo | Tipo | Nome / ID |
|---|---|---|
| audit | `aws_cloudtrail` | cc-sp-trail |
| audit | `aws_cloudwatch_log_group` | /cc/sp/cloudtrail |
| audit | `aws_cloudwatch_log_metric_filter` | access-denied |
| audit | `aws_cloudwatch_log_metric_filter` | iam-policy-change |
| audit | `aws_cloudwatch_log_metric_filter` | sg-change |
| audit | `aws_cloudwatch_metric_alarm` | cc-sp-audit-access-denied |
| audit | `aws_cloudwatch_metric_alarm` | cc-sp-audit-iam-policy-change |
| audit | `aws_cloudwatch_metric_alarm` | cc-sp-audit-sg-change |
| audit | `aws_iam_role` | cc-sp-cloudtrail-cwl-role |
| audit | `aws_iam_role_policy` | cwl-write |
| audit | `aws_s3_bucket` | cc-sp-cloudtrail-244736565328-sa-east-1 |
| audit | `aws_s3_bucket_lifecycle_configuration` | cc-sp-cloudtrail-244736565328-sa-east-1 |
| audit | `aws_s3_bucket_policy` | cc-sp-cloudtrail-244736565328-sa-east-1 |
| audit | `aws_s3_bucket_public_access_block` | cc-sp-cloudtrail-244736565328-sa-east-1 |
| audit | `aws_s3_bucket_server_side_encryption_configuration` | cc-sp-cloudtrail-244736565328-sa-east-1 |
| catalog | `aws_appautoscaling_policy` | catalog-cpu |
| catalog | `aws_appautoscaling_target` | service/cc-sp-cluster/catalog-orders-service |
| catalog | `aws_cloudwatch_log_group` | /cc/sp/catalog-orders-service |
| catalog | `aws_ecs_service` | catalog-orders-service |
| catalog | `aws_ecs_task_definition` | cc-sp-catalog |
| chat | `aws_appautoscaling_policy` | chat-req |
| chat | `aws_appautoscaling_target` | service/cc-sp-cluster/chat-service |
| chat | `aws_cloudwatch_log_group` | /cc/sp/chat-service |
| chat | `aws_ecs_service` | chat-service |
| chat | `aws_ecs_task_definition` | cc-sp-chat |
| compute | `aws_autoscaling_group` | cc-sp-asg |
| compute | `aws_ecs_capacity_provider` | cc-sp-cp |
| compute | `aws_ecs_cluster` | cc-sp-cluster |
| compute | `aws_ecs_cluster_capacity_providers` | cc-sp-cluster |
| compute | `aws_launch_template` | cc-sp-lt-96b2a2434cba254389d266e195 |
| database | `aws_db_instance` | cc-sp-db |
| database | `aws_db_subnet_group` | cc-sp-db-subnets |
| iam | `aws_iam_instance_profile` | cc-sp-ecs-instance-profile |
| iam | `aws_iam_role` | cc-sp-catalog-task-role |
| iam | `aws_iam_role` | cc-sp-chat-task-role |
| iam | `aws_iam_role` | cc-sp-ecs-instance-role |
| iam | `aws_iam_role` | cc-sp-task-exec-role |
| iam | `aws_iam_role` | cc-sp-worker-task-role |
| iam | `aws_iam_role_policy` | bedrock-model |
| iam | `aws_iam_role_policy` | db-secret |
| iam | `aws_iam_role_policy` | sqs-consume-sns-publish |
| iam | `aws_iam_role_policy` | sqs-send |
| iam | `aws_iam_role_policy_attachment` | cc-sp-ecs-instance-role |
| iam | `aws_iam_role_policy_attachment` | cc-sp-ecs-instance-role |
| iam | `aws_iam_role_policy_attachment` | cc-sp-task-exec-role |
| loadbalancer | `aws_lb` | cc-sp-alb |
| loadbalancer | `aws_lb` | cc-sp-ilb |
| loadbalancer | `aws_lb_listener` | arn:aws:elasticloadbalancing:sa-east-1:244736565328:listener/app/cc-sp-alb/752bd478d79e8843/b102768070bc724f |
| loadbalancer | `aws_lb_listener` | arn:aws:elasticloadbalancing:sa-east-1:244736565328:listener/app/cc-sp-ilb/471680d3ff317724/77da77b8b1ccc539 |
| loadbalancer | `aws_lb_target_group` | cc-sp-tg-catalog |
| loadbalancer | `aws_lb_target_group` | cc-sp-tg-chat |
| messaging | `aws_sns_topic` | cc-sp-alarms |
| messaging | `aws_sns_topic` | cc-sp-order-events |
| messaging | `aws_sns_topic_subscription` | arn:aws:sns:sa-east-1:244736565328:cc-sp-alarms:3cddf7f2-6272-44ae-a9ce-764ae890ff52 |
| messaging | `aws_sqs_queue` | cc-sp-orders |
| messaging | `aws_sqs_queue` | cc-sp-orders-dlq |
| messaging | `aws_sqs_queue_redrive_allow_policy` | https://sqs.sa-east-1.amazonaws.com/244736565328/cc-sp-orders-dlq |
| network | `aws_eip` | eipalloc-0c16c4b8a21fe6223 |
| network | `aws_internet_gateway` | igw-0dc24663511c742d8 |
| network | `aws_nat_gateway` | nat-0ab74cd9687c6f592 |
| network | `aws_route` | r-rtb-06b48f00897e494e11080289494 |
| network | `aws_route` | r-rtb-0d7c1969c726f44871080289494 |
| network | `aws_route_table` | rtb-06b48f00897e494e1 |
| network | `aws_route_table` | rtb-0a4f1a5ab53e96a64 |
| network | `aws_route_table` | rtb-0d7c1969c726f4487 |
| network | `aws_route_table_association` | rtbassoc-00edc3816c0251fcf |
| network | `aws_route_table_association` | rtbassoc-05d728ea2ffcdec46 |
| network | `aws_route_table_association` | rtbassoc-07579010d282ba212 |
| network | `aws_route_table_association` | rtbassoc-083d1bcc2c8cec5ad |
| network | `aws_route_table_association` | rtbassoc-09bb4205fb9a8ec5e |
| network | `aws_route_table_association` | rtbassoc-0a7a1ef5da0346eec |
| network | `aws_subnet` | subnet-001b27d3ddd79fb71 |
| network | `aws_subnet` | subnet-037574623ba0c6beb |
| network | `aws_subnet` | subnet-04c98ac5d65886172 |
| network | `aws_subnet` | subnet-07aa5deb653367622 |
| network | `aws_subnet` | subnet-09cd89cd658076fbc |
| network | `aws_subnet` | subnet-09ff5cd4357464080 |
| network | `aws_vpc` | vpc-0e939e3d096b27d98 |
| network | `aws_vpc_endpoint` | vpce-0781e6c368f806fe9 |
| observability | `aws_cloudwatch_dashboard` | cc-sp |
| observability | `aws_cloudwatch_dashboard` | cc-sp-diagnostico |
| observability | `aws_cloudwatch_log_metric_filter` | errors |
| observability | `aws_cloudwatch_log_metric_filter` | errors |
| observability | `aws_cloudwatch_log_metric_filter` | errors |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-5xx |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-app-errors |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-asg-capacity |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-cluster-cpu |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-cluster-mem |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-dlq-not-empty |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-latency-p95 |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-queue-age |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-rds-connections |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-rds-cpu |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-tasks-catalog-orders-service |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-tasks-chat-service |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-tasks-order-worker |
| observability | `aws_cloudwatch_metric_alarm` | cc-sp-unhealthy |
| registry | `aws_ecr_lifecycle_policy` | cc-sp/catalog-orders-service |
| registry | `aws_ecr_lifecycle_policy` | cc-sp/chat-service |
| registry | `aws_ecr_lifecycle_policy` | cc-sp/order-worker |
| registry | `aws_ecr_repository` | cc-sp/catalog-orders-service |
| registry | `aws_ecr_repository` | cc-sp/chat-service |
| registry | `aws_ecr_repository` | cc-sp/order-worker |
| registry | `terraform_data` | 1534cada-7947-4024-d422-b4b4090930a5 |
| registry | `terraform_data` | 313d1aa7-d2b5-5df8-3677-f90a3ea9e653 |
| registry | `terraform_data` | f310e19a-ed09-9c21-caa1-b06390b4298d |
| security | `aws_security_group` | cc-sp-alb |
| security | `aws_security_group` | cc-sp-app |
| security | `aws_security_group` | cc-sp-db |
| security | `aws_security_group` | cc-sp-ilb |
| security | `aws_vpc_security_group_egress_rule` | sgr-04d16d5a4a8fdfc90 |
| security | `aws_vpc_security_group_egress_rule` | sgr-05629cf14820d0929 |
| security | `aws_vpc_security_group_egress_rule` | sgr-099e617fe90aa1bff |
| security | `aws_vpc_security_group_egress_rule` | sgr-0e5ea04880d4ccc3e |
| security | `aws_vpc_security_group_ingress_rule` | sgr-007451cce3156bfec |
| security | `aws_vpc_security_group_ingress_rule` | sgr-043aacc99751514d1 |
| security | `aws_vpc_security_group_ingress_rule` | sgr-06a6eb25d107be442 |
| security | `aws_vpc_security_group_ingress_rule` | sgr-07a4012ac7b33bbf6 |
| security | `aws_vpc_security_group_ingress_rule` | sgr-0af39d84efbdd350e |
| worker | `aws_appautoscaling_policy` | worker-backlog |
| worker | `aws_appautoscaling_target` | service/cc-sp-cluster/order-worker |
| worker | `aws_cloudwatch_log_group` | /cc/sp/order-worker |
| worker | `aws_ecs_service` | order-worker |
| worker | `aws_ecs_task_definition` | cc-sp-worker |
