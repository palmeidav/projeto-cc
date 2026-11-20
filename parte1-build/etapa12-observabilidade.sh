#!/bin/bash
# Etapa 12 do roteiro (12.1 filtros de log e 12.2 alarmes), rodada em bash. Uso: bash etapa12-observabilidade.sh
set -e
source env.sh

# 12.1 Metrica de erros a partir dos logs (nos 3 grupos)
for s in chat-service catalog-orders-service order-worker; do
  aws logs put-metric-filter --log-group-name /cc/$s --filter-name errors \
    --filter-pattern '{ $.level = "ERROR" }' \
    --metric-transformations metricName=AppErrors,metricNamespace=CC,metricValue=1
  echo "filtro AppErrors em /cc/$s"
done

# 12.2 Alarmes
LB=${ALB_ARN#*loadbalancer/}; TGD=${TG_CHAT##*:}
alarm(){ # nome namespace metrica dimensoes estatistica operador limite
  aws cloudwatch put-metric-alarm --alarm-name "$1" --namespace "$2" --metric-name "$3" \
    --dimensions $4 --statistic "$5" --comparison-operator "$6" --threshold "$7" \
    --period 60 --evaluation-periods 2 --treat-missing-data notBreaching \
    --alarm-actions $ALARM_TOPIC --tags Key=project,Value=cc
  echo "alarme $1"; }

alarm cc-unhealthy AWS/ApplicationELB UnHealthyHostCount \
  "Name=TargetGroup,Value=$TGD Name=LoadBalancer,Value=$LB" Maximum GreaterThanThreshold 0
alarm cc-5xx AWS/ApplicationELB HTTPCode_Target_5XX_Count \
  "Name=LoadBalancer,Value=$LB" Sum GreaterThanThreshold 5
alarm cc-dlq-not-empty AWS/SQS ApproximateNumberOfMessagesVisible \
  Name=QueueName,Value=cc-orders-dlq Maximum GreaterThanThreshold 0
alarm cc-queue-age AWS/SQS ApproximateAgeOfOldestMessage \
  Name=QueueName,Value=cc-orders Maximum GreaterThanThreshold 120
alarm cc-asg-capacity AWS/AutoScaling GroupInServiceInstances \
  Name=AutoScalingGroupName,Value=cc-asg Minimum LessThanThreshold 2
alarm cc-cluster-cpu AWS/ECS CPUReservation \
  Name=ClusterName,Value=cc-cluster Average GreaterThanThreshold 85
alarm cc-cluster-mem AWS/ECS MemoryReservation \
  Name=ClusterName,Value=cc-cluster Average GreaterThanThreshold 85
alarm cc-rds-cpu AWS/RDS CPUUtilization \
  Name=DBInstanceIdentifier,Value=cc-db Average GreaterThanThreshold 80
for s in chat-service catalog-orders-service order-worker; do
  alarm cc-tasks-$s ECS/ContainerInsights RunningTaskCount \
    "Name=ClusterName,Value=cc-cluster Name=ServiceName,Value=$s" Minimum LessThanThreshold 1
done
aws cloudwatch put-metric-alarm --alarm-name cc-app-errors --namespace CC --metric-name AppErrors \
  --statistic Sum --period 60 --evaluation-periods 1 --threshold 3 \
  --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching \
  --alarm-actions $ALARM_TOPIC --tags Key=project,Value=cc
echo "alarme cc-app-errors"

# "Alarmes pelo console" do roteiro, feitos pela CLI (como no guia):
aws cloudwatch put-metric-alarm --alarm-name cc-latency-p95 --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime --dimensions Name=LoadBalancer,Value=$LB --extended-statistic p95 \
  --period 60 --evaluation-periods 2 --threshold 5 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching --alarm-actions $ALARM_TOPIC --tags Key=project,Value=cc
echo "alarme cc-latency-p95"
alarm cc-rds-connections AWS/RDS DatabaseConnections \
  Name=DBInstanceIdentifier,Value=cc-db Maximum GreaterThanThreshold 80
