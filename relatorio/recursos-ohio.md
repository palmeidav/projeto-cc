# Recursos criados em Ohio (us-east-2) manualmente (Parte 1)

Gerado da AWS: Resource Groups Tagging API com a tag `project=cc` em us-east-2, mais os papéis e o instance profile do IAM (globais, prefixo `cc-` sem `cc-sp-`) e o Budget.
**86 recursos** listados. Recursos que não aceitam tag, ou que a API de tags não lista (rotas, regras de SG, associações, listeners e políticas inline), não aparecem aqui; estão descritos em `parte1-build/` e em `evidencias-etapa13/00-setup/`.

## Resumo por serviço/tipo

| Serviço | Tipo | Qtd |
|---|---|---|
| application-autoscaling | scalable-target | 3 |
| budgets | budget | 1 |
| cloudwatch | alarm | 14 |
| ec2 | elastic-ip | 1 |
| ec2 | instance | 4 |
| ec2 | internet-gateway | 1 |
| ec2 | launch-template | 1 |
| ec2 | natgateway | 1 |
| ec2 | route-table | 3 |
| ec2 | security-group | 4 |
| ec2 | subnet | 6 |
| ec2 | volume | 3 |
| ec2 | vpc | 1 |
| ec2 | vpc-endpoint | 1 |
| ecr | repository | 3 |
| ecs | capacity-provider | 1 |
| ecs | cluster | 1 |
| ecs | service | 3 |
| ecs | task | 5 |
| ecs | task-definition | 7 |
| elasticloadbalancing | listener | 2 |
| elasticloadbalancing | loadbalancer | 2 |
| elasticloadbalancing | targetgroup | 2 |
| iam | instance-profile | 1 |
| iam | role | 5 |
| logs | log-group | 3 |
| rds | db | 1 |
| rds | subgrp | 1 |
| secretsmanager | secret | 1 |
| sns | topic | 2 |
| sqs | queue | 2 |

## Lista completa

| Serviço | Tipo | Nome / ID |
|---|---|---|
| application-autoscaling | scalable-target | 0ec50c931bed86a8438499a9bbe903e3c2e3 |
| application-autoscaling | scalable-target | 0ec556f6f0e79023430abb686e2ea22229b5 |
| application-autoscaling | scalable-target | 0ec58edc24433add4fa1aba297249627c938 |
| budgets | budget | cc-budget |
| cloudwatch | alarm | cc-5xx |
| cloudwatch | alarm | cc-app-errors |
| cloudwatch | alarm | cc-asg-capacity |
| cloudwatch | alarm | cc-cluster-cpu |
| cloudwatch | alarm | cc-cluster-mem |
| cloudwatch | alarm | cc-dlq-not-empty |
| cloudwatch | alarm | cc-latency-p95 |
| cloudwatch | alarm | cc-queue-age |
| cloudwatch | alarm | cc-rds-connections |
| cloudwatch | alarm | cc-rds-cpu |
| cloudwatch | alarm | cc-tasks-catalog-orders-service |
| cloudwatch | alarm | cc-tasks-chat-service |
| cloudwatch | alarm | cc-tasks-order-worker |
| cloudwatch | alarm | cc-unhealthy |
| ec2 | elastic-ip | eipalloc-0a638c1eef7d914b3 |
| ec2 | instance | i-003be34681d380453 |
| ec2 | instance | i-036f87b829bab4c7e |
| ec2 | instance | i-0b0b2ab08fceab115 |
| ec2 | instance | i-0e0fb3d33369f89f1 |
| ec2 | internet-gateway | igw-080b0a20d424c8c6e |
| ec2 | launch-template | lt-08a8216611a9c79d4 |
| ec2 | natgateway | nat-0c4f9653775e1e458 |
| ec2 | route-table | rtb-030830780fad10035 |
| ec2 | route-table | rtb-08769df36fcf92047 |
| ec2 | route-table | rtb-0a1452aa6b427047c |
| ec2 | security-group | sg-03a78e78a8bdf93fa |
| ec2 | security-group | sg-0834593b15acf537c |
| ec2 | security-group | sg-087df834ca341a6bf |
| ec2 | security-group | sg-0d845e0eb12003722 |
| ec2 | subnet | subnet-00fb0b14859c72709 |
| ec2 | subnet | subnet-02f4f8198c59a304d |
| ec2 | subnet | subnet-0344329b1b0f46aeb |
| ec2 | subnet | subnet-06914cc6fa7f0274c |
| ec2 | subnet | subnet-06990e60a1ef8df8f |
| ec2 | subnet | subnet-0fb31c4a73d9b53fc |
| ec2 | volume | vol-016f1ef5b178577ac |
| ec2 | volume | vol-0641a8b8732e0370f |
| ec2 | volume | vol-0bcb9d7511c8ad7df |
| ec2 | vpc | vpc-0eca349b2c5a4762e |
| ec2 | vpc-endpoint | vpce-097393ab7755529cc |
| ecr | repository | cc/catalog-orders-service |
| ecr | repository | cc/chat-service |
| ecr | repository | cc/order-worker |
| ecs | capacity-provider | cc-cp |
| ecs | cluster | cc-cluster |
| ecs | service | cc-cluster/catalog-orders-service |
| ecs | service | cc-cluster/chat-service |
| ecs | service | cc-cluster/order-worker |
| ecs | task | cc-cluster/509c086091064c6d93e1392d68fd38da |
| ecs | task | cc-cluster/b8f36dcdac9c4d58ac5c798ae09b5974 |
| ecs | task | cc-cluster/c35ef3d16d624f4e99353282020377fd |
| ecs | task | cc-cluster/daa23b71a3d14d22b24eb1ec2bb15728 |
| ecs | task | cc-cluster/fd8777df4ae541cc83f44767319da7f1 |
| ecs | task-definition | cc-catalog:1 |
| ecs | task-definition | cc-catalog:2 |
| ecs | task-definition | cc-chat:1 |
| ecs | task-definition | cc-chat:2 |
| ecs | task-definition | cc-chat:3 |
| ecs | task-definition | cc-worker:1 |
| ecs | task-definition | cc-worker:2 |
| elasticloadbalancing | listener | app/cc-alb/4573f65f6bcbbd4f/8415d8c79d14dc26 |
| elasticloadbalancing | listener | app/cc-ilb/8e7fd21814de3b63/246e901d8cde4695 |
| elasticloadbalancing | loadbalancer | app/cc-alb/4573f65f6bcbbd4f |
| elasticloadbalancing | loadbalancer | app/cc-ilb/8e7fd21814de3b63 |
| elasticloadbalancing | targetgroup | cc-tg-catalog/71c69f2658fa8964 |
| elasticloadbalancing | targetgroup | cc-tg-chat/5ceb4265402321bc |
| iam | instance-profile | cc-ecs-instance-profile |
| iam | role | cc-catalog-task-role |
| iam | role | cc-chat-task-role |
| iam | role | cc-ecs-instance-role |
| iam | role | cc-task-exec-role |
| iam | role | cc-worker-task-role |
| logs | log-group | /cc/catalog-orders-service |
| logs | log-group | /cc/chat-service |
| logs | log-group | /cc/order-worker |
| rds | db | cc-db |
| rds | subgrp | cc-db-subnets |
| secretsmanager | secret | (omitido) |
| sns | topic | cc-alarms |
| sns | topic | cc-order-events |
| sqs | queue | cc-orders |
| sqs | queue | cc-orders-dlq |
