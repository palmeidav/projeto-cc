#!/bin/bash
# Linha do tempo da carga em SP (a cada ~20 s). Uso: bash scripts/monitor-carga-sp.sh <saida.tsv> <minutos>
export AWS_REGION=sa-east-1 AWS_PAGER=""
C=cc-sp-cluster; OUT=$1; END=$(( $(date +%s) + ${2:-30} * 60 ))
TG=$(aws elbv2 describe-target-groups --names cc-sp-tg-chat --query 'TargetGroups[0].TargetGroupArn' --output text)
echo -e "utc\tbrt\tchat_desired\tchat_running\tcatalog_desired\tchat_healthy_tg\tasg_desired\tasg_inservice\tcontainer_instances\tcp_reservation" > "$OUT"
while [ $(date +%s) -lt $END ]; do
  read cd cr < <(aws ecs describe-services --cluster $C --services chat-service --query 'services[0].[desiredCount,runningCount]' --output text)
  kd=$(aws ecs describe-services --cluster $C --services catalog-orders-service --query 'services[0].desiredCount' --output text)
  h=$(aws elbv2 describe-target-health --target-group-arn $TG --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)
  read ad ai < <(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names cc-sp-asg --query 'AutoScalingGroups[0].[DesiredCapacity,length(Instances[?LifecycleState==`InService`])]' --output text)
  ci=$(aws ecs describe-clusters --clusters $C --query 'clusters[0].registeredContainerInstancesCount' --output text)
  cpr=$(aws cloudwatch get-metric-statistics --namespace AWS/ECS/ManagedScaling --metric-name CapacityProviderReservation \
    --dimensions Name=ClusterName,Value=$C Name=CapacityProviderName,Value=cc-sp-cp \
    --start-time $(date -u -v-3M +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Maximum \
    --query 'sort_by(Datapoints,&Timestamp)[-1].Maximum' --output text)
  echo -e "$(date -u +%H:%M:%S)\t$(TZ=America/Sao_Paulo date +%H:%M:%S)\t$cd\t$cr\t$kd\t$h\t$ad\t$ai\t$ci\t$cpr" >> "$OUT"
  sleep 15
done
