# Livraria Nuvem - projeto semestral (Parte 1)

Três serviços Python (FastAPI) + PostgreSQL + SQS.

| Pasta | Porta | Função |
|---|---|---|
| chat-service | 8000 | Vendedor de IA (Bedrock, Converse API com tools). `POST /chat` |
| catalog-orders-service | 8001 | Catálogo, estoque e pedidos (PostgreSQL). Publica no SQS via outbox. |
| order-worker | - | Consome o SQS, confirma o pedido (idempotente) e publica no SNS. |

## Rodar localmente
    docker compose up --build        # vendedor "mock" (sem IA)
    ./teste_local.sh                 # em outro terminal

Com o Bedrock real (precisa de `aws configure` e acesso ao modelo):
    LLM_MODE=bedrock BEDROCK_MODEL_ID=<id-do-modelo> docker compose up --build

## Variáveis de ambiente
Todos: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD, (DB_PORT, DB_SSLMODE), AWS_REGION.
- catalog: QUEUE_URL
- worker: QUEUE_URL, TOPIC_ARN (opcional), PROCESS_DELAY_SECONDS (opcional, simula lentidão)
- chat: CATALOG_URL, BEDROCK_MODEL_ID, LLM_MODE (bedrock | mock)

## Endpoints
- `/health`: vivo (não depende de banco; usado pelo ALB e pelo ECS)
- `/ready`: pronto (verifica o banco)
