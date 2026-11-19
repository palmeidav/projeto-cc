#!/bin/bash
# Prova de que o codigo da Parte 2 nao depende de Ohio (us-east-2).
# 1) busca textual no codigo  2) regioes de todos os ARNs no estado remoto  3) recursos AWS em uso pela stack
# Uso: AWS_PROFILE=insper bash scripts/prova-sem-ohio.sh
set -uo pipefail
cd "$(dirname "$0")/.."
echo "## 1) busca no codigo (infra, services, scripts) por valores de Ohio"
PAT='us-east-2|ohio|vpc-0eca349b2c5a4762e|sg-0834593b15acf537c|ami-0a8975a01978e5b97|nat-0c4f9653775e1e458|c23mtpyyxfro|cc-alb-2058559449|internal-cc-ilb-258031333|us\.anthropic\.|dkr\.ecr\.us-'
grep -rnIiE "$PAT" infra services scripts --exclude-dir=.terraform --exclude='*.tfstate' --exclude='prova-sem-ohio.sh' \
  | grep -v 'modules/iam/main.tf:.*# "us.anthropic' && echo "ENCONTRADO (ver acima)" || echo "nenhuma ocorrencia"
echo "   (ignorado: comentario em modules/iam que documenta o formato us./global. dos perfis do Bedrock)"
echo "## 2) IDs de conta/regiao fixos nos modulos (devem vir de data sources)"
grep -rnIE '[0-9]{12}|(us|sa|eu|ap)-(east|west|south|north|central|southeast|northeast)-[0-9]' infra/modules infra/bootstrap/main.tf \
  | grep -vE '^\S+:\s*#' || echo "nenhum ID de conta nem regiao fixos nos modulos"
echo "## 3) regioes de todos os ARNs no estado remoto de envs/sa-east-1"
( cd infra/envs/sa-east-1 && terraform show -json 2>/dev/null ) \
  | grep -oE 'arn:aws:[a-z0-9-]+:[a-z0-9-]*:' | awk -F: '{r=($4==""?"(global)":$4); print r}' | sort | uniq -c
echo "## 4) servicos/endpoints usados pelas tasks (variaveis de ambiente das task definitions)"
for td in cc-sp-chat cc-sp-catalog cc-sp-worker; do
  aws ecs describe-task-definition --region sa-east-1 --task-definition $td \
    --query 'taskDefinition.containerDefinitions[0].[image, environment[?name!=`DB_PASSWORD`].[name,value]]' --output text
done | grep -oE '([a-z0-9.-]+\.)?(sa-east-1|us-east-2|global)[a-z0-9.:/-]*' | sort -u
echo "## 5) portabilidade: plan do MESMO codigo em us-east-2 (sem mudar arquivos)"
grep -E '^Plan:' evidencias-parte2/fase0-plan/plan-portabilidade-us-east-2.txt
grep -A3 '+ azs' evidencias-parte2/fase0-plan/plan-portabilidade-us-east-2.txt | tr -s ' '
