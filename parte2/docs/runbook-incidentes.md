# Runbook de incidentes: Livraria Nuvem (sa-east-1)

Para quem está de plantão: cada alarme abaixo tem o sintoma, onde olhar, o que fazer e como confirmar
que resolveu. Todos os alarmes notificam o tópico SNS `cc-sp-alarms` (e-mail).
Os tempos citados foram medidos nos testes da Parte 1 (Etapa 13, em Ohio).

**Primeiro passo, sempre (2 min):** abrir o dashboard **`cc-sp-diagnostico`**.
1. Quais alarmes estão em ALARM?
2. É erro da aplicação (`AppErrors`, `ChatDegraded`) ou da infraestrutura (5xx do ALB, tasks em execução)?
3. Logs Insights nos 3 grupos `/cc/sp/*` para ver a causa (consultas abaixo).

```
# erros recentes nos 3 serviços
fields @timestamp, service, message, erro, conversation_id, order_id
| filter level = 'ERROR' | sort @timestamp desc | limit 50

# seguir uma conversa ou um pedido de ponta a ponta (chat -> catalog -> worker)
fields @timestamp, service, message, order_id
| filter conversation_id = '<id>' or order_id = '<id>' | sort @timestamp asc
```

## Severidade
| Nível | Critério | Exemplo |
|---|---|---|
| SEV1 | cliente não consegue conversar nem comprar | `cc-sp-5xx`, `cc-sp-unhealthy`, `cc-sp-tasks-chat-service` |
| SEV2 | compra degradada ou atrasada, sem perda de dados | `cc-sp-queue-age`, `cc-sp-dlq-not-empty`, chat degradado |
| SEV3 | risco futuro ou segurança | `cc-sp-rds-connections`, `cc-sp-cluster-*`, `cc-sp-audit-*` |

## Playbooks

### 1. Chat degradado / Bedrock indisponível (`AppErrors` + `ChatDegraded`, `LLMLatencyMs` sem dados)
- **Sintoma:** `/chat` responde 200 com `degraded=true` e a mensagem "Tive um problema técnico". Nenhum pedido é criado nesse período.
- **Diagnóstico:** procure no Logs Insights `erro` com `AccessDeniedException` (permissão), `ThrottlingException` (limite) ou timeout. No CloudTrail, veja se houve `PutRolePolicy` recente em `cc-sp-chat-task-role` (alarme `cc-sp-audit-iam-policy-change`).
- **Ação:** se a permissão foi alterada, reverta com `terraform apply`, porque o código é a fonte da verdade. Se for limite ou indisponibilidade do modelo, mude `llm_mode = "mock"` só para manter o fluxo de demonstração, ou espere.
- **Verificação:** uma conversa com `degraded=false` e `LLMLatencyMs` voltando a ter dados. Na Parte 1 (13.6), o chat voltou cerca de 20 s depois de restaurar a política.

### 2. Mensagem na DLQ (`cc-sp-dlq-not-empty`)
- **Sintoma:** uma mensagem falhou 3 vezes no worker (`maxReceiveCount = 3`).
- **Diagnóstico:** veja o motivo em `/cc/sp/order-worker` com `message = 'falha ao processar mensagem'` e o campo `erro` (JSON inválido, `order_id` ausente, pedido inexistente).
- **Ação:** *não apague antes de entender.* Se o pedido é válido e o erro era temporário (banco fora do ar), reprocesse com **redrive** da DLQ para `cc-sp-orders`. A confirmação é idempotente (`SELECT ... FOR UPDATE` e status `CONFIRMED`), então reprocessar não duplica. Se a mensagem está corrompida ("poison"), registre o conteúdo no incidente e então faça o purge.
- **Verificação:** DLQ com 0 mensagens e alarme em OK.

### 3. Fila atrasando (`cc-sp-queue-age` > 120 s)
- **Diagnóstico:** veja se o worker está rodando (`cc-sp-tasks-order-worker`) e o backlog por task. A política `worker-backlog` (alvo 5) escala até 5 tasks.
- **Ação:** se o worker estiver no máximo e o banco saturado (veja o playbook 5), aumente `max` do worker no Terraform *e* a capacidade do banco. Se o worker estiver caído, veja os eventos do serviço ECS.
- **Verificação:** `ApproximateAgeOfOldestMessage` caindo e pedidos `CONFIRMED`.

### 4. Alvos não saudáveis ou 5xx (`cc-sp-unhealthy`, `cc-sp-5xx`, `cc-sp-tasks-*`)
- **Diagnóstico:** eventos do serviço ECS (task parada por health check? falta de capacidade, `PENDING`?), saúde dos alvos no target group e instâncias no ASG.
- **Ação:** o ECS substitui a task sozinho (Parte 1, 13.1: substituta healthy em cerca de 1 min, 220/220 respostas 200) e o ASG substitui a instância (13.4: cerca de 18 s de falha no chat quando as 2 tasks estavam na mesma máquina, corrigido com o espalhamento por instância). Se o deploy novo falhar, o circuit breaker faz rollback sozinho. Intervenha só se o problema persistir mais de 5 min: veja o `/ready` (dependências) e os logs da task.
- **Verificação:** alvos healthy e `/health` 200 pelo ALB.

### 5. Banco sob pressão (`cc-sp-rds-connections` > 60, `cc-sp-rds-cpu` > 80)
- **Contexto:** o db.t4g.micro esgotou conexões sob carga na Parte 1 (cerca de 70 conexões, 80–85% de CPU). Por isso o alarme fica em 60, antes do limite.
- **Ação:** reduza o `DB_POOL_MAX` dos serviços ou o `max` do autoscaling (cada task abre até 10 conexões), ou aumente a classe da instância (`db_instance_class`) no Terraform. Num failover Multi-AZ, o `/ready` cai por cerca de 15 s e o `/health` continua 200 (Parte 1, 13.7).

### 6. Auditoria (`cc-sp-audit-iam-policy-change`, `cc-sp-audit-sg-change`, `cc-sp-audit-access-denied`)
- **Diagnóstico:** use o Logs Insights em `/cc/sp/cloudtrail`.
  ```
  fields eventTime, eventName, userIdentity.arn, requestParameters.roleName, requestParameters.groupId, errorCode
  | filter eventName in ['PutRolePolicy','AttachRolePolicy','AuthorizeSecurityGroupIngress','RevokeSecurityGroupIngress'] or ispresent(errorCode)
  | sort eventTime desc | limit 50
  ```
- **Ação:** se a mudança não foi planejada, rode `terraform plan` para ver a divergência (*drift*) e `terraform apply` para voltar ao estado do código. Se a credencial for suspeita, revogue as sessões do papel. Os arquivos da trilha têm validação de integridade (`aws cloudtrail validate-logs`).

## Depois do incidente (registro em até 24 h)
1. Linha do tempo em UTC: detecção (alarme), diagnóstico, ação e normalização.
2. Impacto: requisições com erro, pedidos afetados e se houve perda de dados (esperado: nenhuma).
3. Causa raiz e o que mudou no código (`git log`), no alarme ou no runbook.
