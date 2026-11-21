# Livraria Nuvem: comércio conversacional na AWS

Projeto semestral de Computação em Nuvem (Insper). Um vendedor de IA (Amazon Bedrock, Claude Haiku 4.5)
conversa com o cliente, consulta o catálogo e registra pedidos, sobre ECS em EC2 com ALB, RDS Multi-AZ,
SQS com DLQ, SNS e CloudWatch.

## Índice

| Etapa | Onde está | O que tem |
|---|---|---|
| **Parte 1: Ohio (us-east-2), manual** (console e CLI, sem IaC) | [`parte1-build/`](parte1-build/) | comandos, JSONs (task definitions, políticas IAM, autoscaling, launch template), dashboards e scripts usados para montar a infraestrutura |
| | [`evidencias-etapa13/`](evidencias-etapa13/) | testes de escalabilidade e resiliência (carga, DLQ, idempotência, troca de task e de instância, failover do RDS, falha do LLM) com prints. **Resumo: [`evidencias-etapa13/RESUMO.md`](evidencias-etapa13/RESUMO.md)** |
| | `chat-service/`, `catalog-orders-service/`, `order-worker/` | código dos 3 serviços que rodou em Ohio (v2, com `conversation_id` nos logs) |
| **Parte 2: São Paulo (sa-east-1), Terraform** | [`parte2/`](parte2/) | infraestrutura inteira como código: [`parte2/infra/`](parte2/infra/) (bootstrap do estado remoto, 11 módulos, `envs/sa-east-1`), [`parte2/services/`](parte2/services/) (código dos serviços) |
| | [`parte2/evidencias-parte2/`](parte2/evidencias-parte2/) | plans, applies, jornada CONFIRMED, rolling deploy sem queda, prova de que nada depende de Ohio, CloudTrail e prints. **Resumo: [`parte2/evidencias-parte2/RESUMO.md`](parte2/evidencias-parte2/RESUMO.md)** |
| **Relatório técnico** | **[PDF](relatorio/Relatorio-Livraria-Nuvem.pdf)** | decisões, resultados e análise por dimensão da rubrica; anexos com a lista de recursos criados ([Ohio](relatorio/recursos-ohio.md), [SP](relatorio/recursos-sp.md)) |
| **Diagramas da arquitetura** | [Ohio](parte2/docs/diagrama-arquitetura-ohio.png) · [São Paulo](parte2/docs/diagrama-arquitetura.png) | caminho de um pedido numerado de 1 a 8 (fonte: `parte2/docs/diagrama_arquitetura.py`, `bash parte2/docs/gerar-diagrama.sh [sp\|ohio]`) |
| **Operação** | [`parte2/docs/runbook-incidentes.md`](parte2/docs/runbook-incidentes.md) | runbook de resposta a incidentes |

## Como rodar

**Localmente (sem AWS):**
```bash
docker compose up --build        # vendedor "mock" (sem IA)
./teste_local.sh                 # em outro terminal: jornada completa até o pedido CONFIRMED
```

**Parte 2 na AWS (Terraform >= 1.10, AWS CLI v2, Docker):**
```bash
export AWS_PROFILE=<seu-perfil>
cd parte2
bash scripts/fase0-checagens.sh sa-east-1               # só leitura: AZs, tipos, Bedrock na região
cd infra/bootstrap && terraform init && terraform apply  # bucket S3 do estado remoto (1 vez)
terraform output -raw backend_hcl > ../envs/sa-east-1/backend.hcl
cd ../envs/sa-east-1
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan     # cria tudo, inclusive build/push das imagens no ECR da região
```
O `apply` imprime `alb_url`. Teste com `curl $ALB/health` e `POST $ALB/chat`. Detalhes em [`parte2/README.md`](parte2/README.md).

**Parte 1:** foi montada manualmente, passo a passo, conforme o roteiro do curso. Os comandos e arquivos estão em
`parte1-build/` (o `env.sh` com os IDs da conta não está no repositório).

## Serviços

| Pasta | Porta | Função |
|---|---|---|
| chat-service | 8000 | Vendedor de IA (Bedrock, Converse API com tools). `POST /chat` |
| catalog-orders-service | 8001 | Catálogo, estoque e pedidos (PostgreSQL). Publica no SQS via outbox. |
| order-worker | - | Consome o SQS, confirma o pedido (idempotente) e publica no SNS. |

Variáveis de ambiente: todos usam DB_HOST, DB_NAME, DB_USER, DB_PASSWORD (do Secrets Manager na AWS), AWS_REGION.
O catalog usa QUEUE_URL; o worker usa QUEUE_URL e TOPIC_ARN; o chat usa CATALOG_URL, BEDROCK_MODEL_ID e LLM_MODE (bedrock | mock).

Endpoints: `/health` responde se o serviço está vivo (não depende do banco; usado pelo ALB e pelo ECS). `/ready` responde se está pronto (verifica o banco).
