#!/bin/bash
# Fase 0 (so leitura): o que a regiao alvo oferece antes do primeiro apply.
# Uso: AWS_PROFILE=insper bash scripts/fase0-checagens.sh [regiao]
set -uo pipefail
R=${1:-sa-east-1}; export AWS_PAGER=""
echo "## identidade"; aws sts get-caller-identity --query '[Account,Arn]' --output text
echo "## AZs em $R"; aws ec2 describe-availability-zones --region $R --query 'AvailabilityZones[?State==`available`].ZoneName' --output text
echo "## t3.medium por AZ"; aws ec2 describe-instance-type-offerings --region $R --location-type availability-zone \
  --filters Name=instance-type,Values=t3.medium --query 'InstanceTypeOfferings[].Location' --output text
echo "## db.t4g.micro postgres (versao padrao)"; aws rds describe-db-engine-versions --region $R --engine postgres --default-only \
  --query 'DBEngineVersions[0].EngineVersion' --output text
aws rds describe-orderable-db-instance-options --region $R --engine postgres --db-instance-class db.t4g.micro \
  --query 'length(OrderableDBInstanceOptions[?MultiAZCapable])' --output text | sed 's/^/opcoes Multi-AZ para db.t4g.micro: /'
echo "## AMI ECS AL2023"; aws ssm get-parameter --region $R --name /aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id --query Parameter.Value --output text
echo "## Bedrock: perfis de inferencia com Haiku 4.5"; aws bedrock list-inference-profiles --region $R \
  --query "inferenceProfileSummaries[?contains(inferenceProfileId,'haiku-4-5')].[inferenceProfileId,status]" --output text
echo "## Bedrock: modelo base na regiao"; aws bedrock list-foundation-models --region $R --by-provider anthropic \
  --query "modelSummaries[?contains(modelId,'haiku-4-5')].[modelId,join(',',inferenceTypesSupported)]" --output text
echo "## o que ja existe com prefixo cc-sp (deve estar vazio)"
aws ec2 describe-vpcs --region $R --filters Name=tag:project,Values=cc --query 'Vpcs[].VpcId' --output text
aws iam list-roles --query "Roles[?starts_with(RoleName,'cc-sp-')].RoleName" --output text
aws s3api list-buckets --query "Buckets[?starts_with(Name,'cc-tfstate-')].Name" --output text
