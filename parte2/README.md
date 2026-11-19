# Livraria Nuvem: Parte 2 (Terraform)

Toda a infraestrutura da Parte 1 como código, parametrizada por região (padrão `sa-east-1`).
Nada é reaproveitado de Ohio: nenhum ID, ARN, AMI, imagem ou estado.

```
services/                  código dos 3 serviços (v2, com conversation_id nos logs)
infra/bootstrap/           bucket S3 do estado remoto (estado local, roda 1 vez)
infra/modules/             network, security, database, messaging, iam, registry,
                           compute, loadbalancer, service (genérico, usado 3x), observability, audit
infra/envs/sa-east-1/      composição dos módulos + backend S3 + terraform.tfvars
scripts/fase0-checagens.sh checagens só de leitura da região alvo
scripts/prova-sem-ohio.sh  prova de ausência de dependências de Ohio
docs/runbook-incidentes.md runbook de resposta a incidentes
```

## Ordem de execução

```bash
export AWS_PROFILE=insper
bash scripts/fase0-checagens.sh sa-east-1          # só leitura

cd infra/bootstrap
terraform init && terraform apply                  # cria o bucket de estado
terraform output -raw backend_hcl > ../envs/sa-east-1/backend.hcl

cd ../envs/sa-east-1
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
```

Requisitos locais: Terraform >= 1.10, AWS CLI v2, Docker (o `apply` compila e publica as
imagens com `--platform linux/amd64` no ECR da própria região).

## Decisões
- **Segredo do banco**: `manage_master_user_password` faz o RDS gerar e guardar a senha no
  Secrets Manager. A senha nunca passa pelo Terraform nem fica no estado; as tasks recebem só o ARN.
- **Imagens**: `terraform_data` + `local-exec` (build/push) com tag = hash do código-fonte.
  Sem provider extra e sem token do ECR no estado.
- **Nomes**: prefixo `cc-<env>` (ex.: `cc-sp-*`). IAM é global e a Parte 1 continua na mesma conta.
- **Lições da Parte 1 já no código**: alvo do chat 600 req/min por task, alarme de conexões
  do RDS em 60, chat e catalog espalhados por AZ **e** por instância, tags também nos volumes
  EBS, papel do chat restrito ao modelo configurado.
- **Destruição reproduzível**: `skip_final_snapshot`, `deletion_protection = false`,
  `force_delete` no ECR e no ASG.
