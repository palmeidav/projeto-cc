#!/bin/bash
# Registra a linha do tempo do teste 13.2 (a cada ~20 s). Uso: bash monitor-carga.sh <saida.tsv> <minutos>
source env.sh
export AWS_PROFILE=insper
OUT=$1; END=$(( $(date +%s) + ${2:-45} * 60 ))
echo -e "utc\tbrt\tchat_desired\tchat_running\tchat_pending\ttasks_provisioning\tchat_healthy_targets\tasg_desired\tasg_inservice\tcontainer_instances\tcp_reservation" > "$OUT"
while [ $(date +%s) -lt $END ]; do
  read d r p < <(aws ecs describe-services --cluster cc-cluster --services chat-service \
    --query 'services[0].[desiredCount,runningCount,pendingCount]' --output text)
  prov=$(aws ecs list-tasks --cluster cc-cluster --query taskArns --output text | tr '\t' ' ' | xargs -n 100 aws ecs describe-tasks --cluster cc-cluster --query "length(tasks[?lastStatus=='PROVISIONING'])" --output text --tasks 2>/dev/null)
  h=$(aws elbv2 describe-target-health --target-group-arn $TG_CHAT --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)
  read ad ai < <(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names cc-asg \
    --query 'AutoScalingGroups[0].[DesiredCapacity,length(Instances[?LifecycleState==`InService`])]' --output text)
  ci=$(aws ecs describe-clusters --clusters cc-cluster --query 'clusters[0].registeredContainerInstancesCount' --output text)
  cpr=$(aws cloudwatch get-metric-statistics --namespace AWS/ECS/ManagedScaling --metric-name CapacityProviderReservation \
    --dimensions Name=ClusterName,Value=cc-cluster Name=CapacityProviderName,Value=cc-cp \
    --start-time $(date -u -v-3M +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Maximum \
    --query 'sort_by(Datapoints,&Timestamp)[-1].Maximum' --output text)
  echo -e "$(date -u +%H:%M:%S)\t$(TZ=America/Sao_Paulo date +%H:%M:%S)\t$d\t$r\t$p\t$prov\t$h\t$ad\t$ai\t$ci\t$cpr" >> "$OUT"
  sleep 15
done
