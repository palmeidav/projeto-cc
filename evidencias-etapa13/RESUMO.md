# RESUMO - Etapa 13 (Livraria Nuvem, Parte 1, Ohio us-east-2)

Conta 244736565328 (profile `insper`, SSO), executado em 18/11/2026 por pedrohav.
Horários em UTC (BRT = UTC-3). Todas as saídas brutas, com horário e comando, estão nas subpastas desta pasta.

## Contexto: a Parte 1 foi reconstruída nesta conta

O portão do passo 2 falhou: `cc-cluster` não existia na 244736565328 (`reason: MISSING`, zero recursos com `project=cc`;
ver `01-antes/portao-cluster.txt`). Por decisão do grupo, a Parte 1 foi **reconstruída do zero** nesta conta seguindo
`roteiro_parte1_aws_ohio.pdf` (Etapas 0 a 12) e só então rodada a Etapa 13 deste etapa13.md.
Tempo total da reconstrução: ~40 min (17:37 a 18:09 UTC). Arquivos de apoio (env.sh, td-*.json, tt-*.json,
dashboard-cc.json, etc.) em `../parte1-build/`.

| Etapa do roteiro | Resultado | Evidência |
|---|---|---|
| 0 Ambiente | conta vazia; Bedrock Haiku 4.5 ok; Budget `cc-budget` US$ 50 (80% real / 100% previsto) | `00-setup/fase0.txt` |
| 1 Aplicação | `docker compose` + `teste_local.sh`: pedido CONFIRMED em ~400 ms, idempotência 201/200 | `00-setup/etapa1-teste-local.txt` |
| 2 Rede | VPC 10.0.0.0/16, 6 sub-redes em 2a/2b, IGW, 1 NAT (pronto em 1m48s), endpoint S3, 4 SGs | `00-setup/etapa2-rede.txt` |
| 3 RDS | Postgres 18.3 Multi-AZ (primário 2b, standby 2a), privado, senha no Secrets Manager; ~15 min | `00-setup/etapa3-rds.txt` |
| 4 ECR | 3 repositórios (scanOnPush), imagens v1 linux/amd64 | `00-setup/etapa4-ecr.txt` |
| 5 Mensageria | cc-orders (visibilidade 60 s, maxReceiveCount 3) + cc-orders-dlq; SNS cc-order-events e cc-alarms (e-mail confirmado) | `00-setup/etapa5-mensageria.txt` |
| 6 IAM | 5 papéis + instance profile | `00-setup/etapa6-iam.txt` |
| 7 Capacidade | cluster (Container Insights), LT cc-lt **t3.medium**, ASG 2/2/4, CP cc-cp alvo 80% | `00-setup/etapa7-capacidade.txt` |
| 8 ALBs | cc-alb (público) e cc-ilb (interno), TGs com deregistration 30 s | `00-setup/etapa8-alb.txt` |
| 9 Serviços | chat 2, catalog 2, worker 1; spread AZ + binpack memória; circuit breaker | `00-setup/etapa9-servicos.txt` |
| 10 MVP | jornada real com Bedrock: pedido `98a686dd2ed4` criado 18:08:55.265, CONFIRMED 18:08:56.278 | `00-setup/etapa10-mvp.txt` |
| 11 Autoscaling | chat ALBRequestCountPerTarget 50 (2-6); catalog CPU 60 (2-6); worker backlog m1/m2 = 5 (1-5) | `00-setup/etapa11-autoscaling.txt` |
| 12 Observabilidade | filtro AppErrors nos 3 grupos, 14 alarmes, dashboard `cc` (10 gráficos) | `00-setup/etapa12-observabilidade.txt` |

## Resultado de cada teste

| Passo / teste | Resultado |
|---|---|
| 3 - Evidências do ANTES | **PASSOU** (chat 2/2, catalog 2/2, worker 1/1; 2 alvos healthy por TG em instâncias diferentes; /health 200) |
| 4 - Logs correlacionáveis (v2) | **PASSOU** (mesma conversation_id no chat, catalog e worker no Logs Insights) |
| 13.5 - Mensagem venenosa (DLQ) | **PASSOU** (3 tentativas -> DLQ; alarme cc-dlq-not-empty em ALARM -> SNS cc-alarms) |
| 13.5 - Duplicidade POST /orders (Idempotency-Key) | **PASSOU** (201 + 200 `idempotent_replay`; 1 único pedido no banco) |
| 13.5 - Duplicidade SQS (worker) | **PASSOU** ("mensagem duplicada ignorada"; confirmed_at inalterado) |
| 13.2 - Elasticidade sob carga (tasks + instâncias) | **PASSOU**, com a ressalva do tempo de reação (ver abaixo) |
| 13.2 - Teste curto com Bedrock real (LLMLatencyMs) | **PASSOU** |
| 7 - Fechamento | **PASSOU** (com 2 pendências decididas pelo Pedro, ver passo 7) |

## Números principais

### Estado: antes / pico / depois

| | Antes (18:50) | Pico (19:00-19:09) | Depois (19:53) |
|---|---|---|---|
| Tasks chat-service | 2 | **6** | 2 |
| Tasks catalog-orders-service | 2 | **6** | 2 |
| Tasks order-worker | 1 | 1 | 1 |
| Instâncias ASG (desejado) | 3 | **4** | 3 |
| CapacityProviderReservation | 80 | 106,7 -> 100 -> 80 | 80 |

### Carga (hey, 80 conexões, POST /chat em LLM_MODE=mock)

| | Carga 1: `hey -z 5m` (18:50:49-18:55:49) | Carga 2: `hey -z 10m` (18:59:12-19:09:13) |
|---|---|---|
| Configuração | 2 chat / 2 catalog / 3 instâncias | 6 chat / 6 catalog / 4 instâncias |
| Requisições/s | **234,5** (70.414 req) | **190,9** (114.710 req) |
| Latência p50 / p95 / p99 / máx | 289 ms / 672 ms / 1,43 s / 3,83 s | 255 ms / 1,38 s / 2,86 s / 5,48 s |
| Erros | 1 x HTTP 502 (0,001%) | 2 x HTTP 502 (0,002%) |
| Req/min por task do chat (alvo 50) | até 8.092 | - |
| CPU das tasks (% da reserva, média) | chat ~170%, catalog ~167% | chat ~47%, catalog ~47% |
| CPU do RDS / conexões | ~45-50% / 41 | **80-85%** / **70** |

### Tempos de scale-out e scale-in

| Evento | Horário (UTC) | Tempo |
|---|---|---|
| Início da carga 1 | 18:50:49 | - |
| Alarme AlarmHigh do chat -> desired 2->6 | 18:55:58 | **~5 min de reação** (3 pontos de 1 min + atraso da métrica do ALB) |
| catalog desired 2->6 (CPU) | 18:56:06 | - |
| chat 6/6 running e healthy no TG | 18:56:56 | **~58 s** do pedido de scale-out até healthy |
| CapacityProviderReservation 80 -> 106,7 | 18:58:18 | - |
| ASG desired 3->4 | 18:58:59 | ~40 s depois do CPR passar de 100 |
| EC2 i-048df9755deb5c4cd lançada | 18:59:11 | - |
| 4ª instância registrada no cluster ECS | 18:59:44 | **~33 s** do launch ao registro |
| Fim da carga 2 | 19:09:13 | - |
| catalog 6->5->4->3->2 | 19:22:52 ... 19:32:52 | ~14 min até o 1º passo; 1 passo a cada 3-4 min |
| chat 6->5->4->3->2 | 19:27:39 ... ~19:36:39 | ~18 min até o 1º passo; 1 passo a cada 3 min (cooldown 120 s) |
| CP pede 4->3; ASG recusa (instâncias protegidas) | 19:46:29 | proteção gerenciada funcionando |
| ECS libera a instância vazia; ASG termina i-0e0382c29c6741a01 | 19:47:21-19:48:05 | **~38 min** do fim da carga até o ASG voltar a 3 |

Tasks em PROVISIONING: **nenhuma**. As 4 tasks novas do chat couberam na 3ª instância, que estava vazia
(reserva do alvo 80%); a 4ª instância foi pedida depois, por precaução, quando o CPR passou de 100.

### Bedrock real (Haiku 4.5) - teste curto (19:52:52-19:53:03)

6 requisições sequenciais, todas HTTP 200 e degraded=false. Turno de ponta a ponta: **1,9 a 2,9 s** (contra ~0,29 s em mock).
`CC/LLMLatencyMs` (12 chamadas, 2 por turno): **mín 666 ms, média ~990 ms, máx 1.696 ms**.

### DLQ (13.5)

`poison` enviada às ~18:34:2x; falhas (JSONDecodeError) às 18:34:30, 18:35:30 e 18:36:30; na DLQ às ~18:37:30
(visto às 18:37:45, **DLQ = 1**); alarme `cc-dlq-not-empty` **OK -> ALARM às 18:41:53**, aviso enviado ao SNS cc-alarms.

## Achados da análise (para a defesa)

1. **Por que o ASG fica com 3 instâncias ("ponto aberto" do guia).** O `targetCapacity=80` do CP exige que no
   máximo 80% das instâncias estejam ocupadas. Com tasks nas 2 instâncias originais, 2/2 = 100% > 80%, então o CP
   mantém uma 3ª instância vazia (2/3 = 67%) e a métrica fica cravada em 80, sem cair. Não é bug, é a folga do alvo de 80%.
   Custo: ~US$ 1/dia (1 t3.medium). Decisão: **manter** (mantido no passo 7).
2. **O target tracking reage em ~5 min.** O AlarmHigh exige 3 pontos de 1 min e a métrica do ALB atrasa ~2-3 min.
   Na carga 1 (5 min) o scale-out só começou 9 s depois do fim. Por isso rodamos a carga 2 (10 min). Para testes curtos
   ou picos rápidos, considerar step scaling ou alvo menor.
3. **O gargalo migrou da CPU das tasks para o RDS.** Com 2+2 tasks, chat e catalog saturavam (~170% da reserva).
   Com 6+6 tasks, elas caíram para ~47%, mas o RDS db.t4g.micro foi a 80-85% de CPU (alarme `cc-rds-cpu` disparou
   às 19:06:28) e a vazão não aumentou (191 contra 234 req/s), com cauda pior. Mais tasks não resolvem quando o banco
   é o limite.
4. **Esgotamento de conexões do RDS.** `max_connections` do t4g.micro = LEAST(memória/9531392, 5000), ~80 menos os slots
   reservados. Com 12 tasks (pool de até 10 cada) chegamos a 70 conexões. Às 19:11:51 o ECS iniciou 1 task extra de
   catalog para rebalancear AZ; ela **não conseguiu conectar** ("remaining connection slots are reserved"), ficou
   unhealthy e foi parada às 19:13:18 (`06-carga/13.2-scale-in.txt`). Sem impacto visível ao cliente além dos 502.
   **O alarme `cc-rds-connections` (limite 80) nunca dispararia antes do esgotamento.** O limite 80 era uma estimativa do
   guia e agora está conferido como alto demais.
   Recomendações: alarme em ~60; `DB_POOL_MAX` menor por task ou RDS Proxy; classe maior de RDS.
5. **Scale-in seguro.** O ASG recusou o scale-in enquanto todas as instâncias estavam protegidas. Só depois que o ECS
   liberou a instância sem tasks ela foi terminada, sem interromper nenhuma task.
6. **Comportamento do LLM (não é infra).** Na conversa do passo 4, o Haiku fechou o pedido no 2º turno sem esperar o
   "confirmo" pedido no prompt. O 3º turno não duplicou o pedido.

## Prints (por teste)

| Teste | Arquivo |
|---|---|
| Antes: TG chat healthy | `prints/01-antes/01-tg-chat-healthy.png` |
| Antes: TG catalog healthy | `prints/01-antes/02-tg-catalog-healthy.png` |
| Antes: Launch Template | `prints/01-antes/03-launch-template-cc-lt.png` |
| Antes: Capacity Provider / cluster | `prints/01-antes/04-capacity-provider-cc-cp.png` |
| Antes: ASG | `prints/01-antes/05-asg-cc-asg.png` |
| Antes: dashboard cc (console) | `prints/01-antes/06-dashboard-cc.png` |
| Antes: 10 gráficos do dashboard (API) | `prints/01-antes/dash-01..10-*.png` |
| Passo 4: Logs Insights, 3 grupos, conversation_id | `prints/04-logs-insights-conversation-id.png` |
| 13.5: fila e DLQ | `prints/05-dlq-duplicidade/02-grafico-fila-dlq.png` |
| 13.5: alarme cc-dlq-not-empty In alarm | `prints/05-dlq-duplicidade/03-console-alarme-dlq.png` |
| 13.2 pico: chat 6 tasks healthy | `prints/06-carga/01-pico-chat-6-tasks.png` |
| 13.2 pico: TG chat | `prints/06-carga/02-pico-tg-chat-6-healthy.png` |
| 13.2 tasks 2->6->2 | `prints/06-carga/03-tasks-pico-e-volta.png` |
| 13.2 ASG 3->4->3 | `prints/06-carga/04-asg-pico-e-volta.png` |
| 13.2 CapacityProviderReservation | `prints/06-carga/05-cpr-pico-e-volta.png` |
| 13.2 ALB requisições e 5xx | `prints/06-carga/06-alb-requisicoes.png` |
| 13.2 ALB latência p50/p95/p99 | `prints/06-carga/07-alb-latencia.png` |
| 13.2 gargalo RDS | `prints/06-carga/08-rds-gargalo.png` |
| 13.2 LLMLatencyMs (Bedrock real) | `prints/06-carga/09-llm-latency-bedrock-real.png` |

As telas de console foram capturadas abrindo uma janela do Chrome só com a página da AWS e recortando apenas essa janela.
Os gráficos foram gerados pela API `cloudwatch get-metric-widget-image` (mesmas métricas do console).

## Mudança de código do passo 4 (imagens v2)

Diff completo em `04-logs-correlacionaveis/diff-v1-v2.patch` (3 arquivos, +17/-9). Antes, o conversation_id não
atravessava os serviços: o chat só logava em erro, o catalog não recebia o id e o worker logava só message_id.

- **chat-service**: envia o header `X-Conversation-Id` ao catálogo; loga "turno de conversa" com conversation_id em todo turno.
- **catalog-orders-service**: lê `X-Conversation-Id`; inclui conversation_id nos logs "pedido criado" e "pedido repetido
  (idempotência)" e **no payload do outbox**, para que o id chegue ao worker pela fila.
- **order-worker**: `process()` devolve também os dados da mensagem; logs "pedido confirmado" e "mensagem duplicada
  ignorada" passam a ter order_id e conversation_id.
- Sem mudança de comportamento (idempotência, DLQ, outbox e API iguais).

Imagens: `244736565328.dkr.ecr.us-east-2.amazonaws.com/cc/{chat-service,catalog-orders-service,order-worker}:v2`
(linux/amd64). Task definitions: `cc-chat:2`, `cc-catalog:2`, `cc-worker:2` (só a imagem mudou em relação à rev. 1).
`cc-chat:3` = `cc-chat:2` + `LLM_MODE=mock` (usada só no teste de carga). Deploy v2 estável às 18:22:34, sem rollback.

Prova (Logs Insights, os 3 grupos, conversation_id `afda496c45d1449daad851cc1ee16f85`):

| UTC | serviço | mensagem | order_id |
|---|---|---|---|
| 18:23:03.810 | chat-service | turno de conversa | - |
| 18:23:05.410 | catalog-orders | pedido criado | 1874fb774fc0 |
| 18:23:06.094 | order-worker | pedido confirmado | 1874fb774fc0 |
| 18:23:06.414 | chat-service | turno de conversa | - |
| 18:23:07.844 | chat-service | turno de conversa | - |

## Confirmação do passo 7 (fechamento, 19:53 UTC)

- ASG: mín 2, **desejado 3**, máx 4. A 3ª instância é a folga do alvo de 80% (hoje `i-048df9755deb5c4cd`, 0 tasks).
  Decidido com o Pedro: **manter**.
- Serviços: chat-service 2/2 em `cc-chat:2` (imagem v2, sem LLM_MODE, ou seja, **Bedrock real**), catalog 2/2
  (`cc-catalog:2`), worker 1/1 (`cc-worker:2`).
- Targets: 2 healthy por TG, em instâncias diferentes. `curl http://$ALB_DNS/health` -> **HTTP 200**.
- Tags: todos os recursos criados têm `project=cc` (contagem por tipo em `07-fechamento/tags-project-cc.txt`).
  Os 3 volumes EBS de 30 GB das instâncias estavam sem a tag (o LT do roteiro só tagueia a instância) e foram tagueados
  à mão. **O Launch Template não foi alterado**, a pedido do Pedro, então instâncias novas voltam a nascer com volume
  sem tag. Ficam sem tag, por serem criados automaticamente pela AWS: 10 ENIs (ALB, NAT, RDS, EC2), a route table main,
  o SG default e a NACL default da VPC.
- **DLQ com 1 mensagem (`poison` do 13.5) e alarme `cc-dlq-not-empty` em ALARM, mantidos de propósito** para mostrar
  no vídeo. O Pedro esvazia depois (`aws sqs purge-queue --queue-url <DLQ_URL>`), e o alarme volta a OK.
- Outros alarmes em ALARM: só os *AlarmLow* do target tracking (pedem scale-in com tráfego baixo; normal).

## Desvios do roteiro da Ana Clara e por quê

| Desvio | Por quê |
|---|---|
| Parte 1 reconstruída do zero na conta 244736565328 | `cc-cluster` não existia nesta conta (portão do passo 2); decisão do grupo |
| `aws configure sso` (profile insper) no lugar de `aws configure` com chaves | a conta é acessada por IAM Identity Center |
| AWS CLI v2 instalada pelo .pkg oficial só para o usuário; `hey` v0.1.4 compilado em container Go | sem Homebrew no Mac (instalar pede sudo); o binário oficial do hey não está mais disponível |
| `perl` no lugar de `envsubst` | gettext não instalado; o perl troca só os `${VAR}`, com o mesmo efeito |
| Tag `project=cc` (+ Name) também em IGW, route tables, EIP, NAT, endpoint S3, SGs, listeners, LT, task definitions, alvos escaláveis, alarmes, segredo e volumes EBS | pedido do Pedro: "tag project=cc em tudo" |
| `t3.medium` mantido (sem o desvio m7i-flex.large do guia) | o dry-run nesta conta aceitou t3.medium |
| Alarmes cc-latency-p95 e cc-rds-connections criados pela CLI (o roteiro manda pelo console) | igual ao guia; reprodutível |
| Correção de logs com imagens v2 (passo 4) | o conversation_id não atravessava os serviços (rubrica: logs correlacionáveis) |
| Print do Logs Insights via widget de dashboard (`cc-correlacao`) | o console não aceita consulta e grupos pré-preenchidos pela URL; o widget roda a mesma consulta sobre os 3 grupos |
| Duplicidade via `aws ssm send-command` + `params.json` | catalog só é alcançável pelo ALB interno; sem execute-command; JSON no body |
| 13.2: segunda carga com `hey -z 10m` (além da de 5 min do roteiro) | o target tracking levou ~5 min para reagir e o scale-out da 1ª carga aconteceu já sem carga |
| Dashboard extra `cc-correlacao` | usado para o print do passo 4 e reaproveitável no 13.8 |

## BÔNUS NÍVEL A (18/11/2026, 20:08-20:47 UTC)

Regras do Pedro para o bônus: não apagar nada, não destruir recursos sem autorização, não mexer na DLQ.
13.3, 13.4 e 13.7 executados com "pode ir" explícito. Evidências em `08-bonus/` e `prints/08-bonus/`.

| Teste | Resultado | Números |
|---|---|---|
| 13.1 Troca de task sem indisponibilidade | **PASSOU** | `/health` 20:08:15-20:12:14: **220/220 HTTP 200**; stop 20:08:39.9 -> substituta healthy 20:09:45 (~65 s); antiga STOPPED 20:09:58 |
| 13.6 Falha do LLM | **PASSOU** | Deny ativo 20:16:4x-20:21:1x; 5/5 respostas amigáveis (HTTP 200, `degraded:true`); **0 pedidos criados** (3 antes, 3 depois); vendedor voltou às 20:21:38, na mesma conversa |
| 13.8 Diagnóstico pela observabilidade | **PASSOU** | alarme `cc-app-errors` OK -> ALARM às 20:18:57 (~1m50s após o 1º erro) -> dashboard: AppErrors=5, ChatDegraded=5, LLMLatencyMs sem dados, ALB 5xx=0, tasks ok -> Logs Insights por conversation_id: `AccessDeniedException ... Converse ... cc-chat-task-role` = causa raiz IAM |
| 13.3 Drenagem + instance refresh | **PASSOU** | `/health` 20:25-20:34: **510/510 HTTP 200** (máx 0,70 s); drenagem de 3 tasks em ~70 s (start-before-stop); refresh **Successful**: 3/3 instâncias trocadas em ~7 min (20:26:53-20:33:50) |
| 13.4 Perda abrupta de instância | **PASSOU** (capacidade e dados), **com achado** | terminate 20:34:38 -> **~18 s de chat indisponível** (7x 502 + 3 timeouts); /health ok às 20:34:56; tudo recuperado em **+44 s** (2/2, 2/2, 1/1; ASG lançou i-0b0b2ab08fceab115); pedidos **idênticos** antes/depois |
| 13.7 Failover do RDS | **PASSOU** | failover 20:36:55 -> completed 20:37:44; primário **2b -> 2a**; `/ready` (consulta o banco) fora ~15 s (2 timeouts); **`/health` 133/133 HTTP 200** (as tasks não morrem); conversa nova ok; pedidos **idênticos** |

### Achados do bônus

7. **Tasks do mesmo serviço podem ficar na mesma instância (13.4).** `spread` por AZ + `binpack` por memória decide no
   momento da colocação. Durante o refresh (e logo após a perda), uma AZ ficou sem instância disponível e as **2 tasks
   do chat foram para a mesma máquina**, então a perda dela derrubou o chat por ~18 s. Depois da recuperação aconteceu de
   novo (as 2 na mesma instância de 2b). Recomendação (defesa e Terraform): `placementConstraints` `distinctInstance`
   no chat e no catalog e/ou o *AZ rebalancing* do ECS; e/ou `desiredCount` mínimo 3.
8. **`/health` sem banco funciona como projetado (13.7):** o banco ficou fora ~15 s e nenhuma task foi morta pelo ECS/ALB.
9. **O alvo de 50 req/min por task é muito baixo:** os dois loops de medição (`/health` + `/ready`, ~230 req/min)
   bastaram para escalar o chat de 2 para 4 (20:42:58 e 20:44:58). Ele volta a 2 sozinho. Calibrar o TargetValue
   com base nos números do 13.2 (por exemplo, ~2.000-3.000 req/min por task em mock).
10. **Detecção em ~2 min (13.8):** o caminho alarme -> dashboard -> Logs Insights por conversation_id localizou a causa
    raiz (IAM) sem acessar as tasks.

### Desvios do bônus

| Desvio | Por quê |
|---|---|
| 13.6: policy `inline` **sobrescrita** com Deny `bedrock:*` (e restaurada do backup `parte1-build/p-chat-backup.json`), em vez de `delete-role-policy` | regra do Pedro: não apagar nada; mesmo efeito (Bedrock indisponível para o chat) |
| 13.3: `"ScaleInProtectedInstances":"Refresh"` no instance refresh | as instâncias são protegidas pelo CP; sem isso o refresh espera até 1 h e falha (previsto no etapa13) |
| 13.4: instância escolhida = a com mais tasks (i-0e11b4cf5d06f56d1, 2 chat + worker) | pior caso; revelou o achado 7 |
| Loops de medição em `/health` e `/ready` (~1 req/s cada) em vez de 0,5 s | o tempo de cada chamada no Mac limita o intervalo real |
| Dashboard extra `cc-diagnostico` | uma tela com o caminho do 13.8 (alarmes -> métricas -> logs) |

### Prints do bônus

| Teste | Arquivo |
|---|---|
| 13.8 caminho de diagnóstico (alarmes, métricas, logs) | `prints/08-bonus/13.8-01-dashboard-diagnostico.png` |
| 13.8 alarme cc-app-errors | `prints/08-bonus/13.8-02-alarme-cc-app-errors.png` |
| 13.7 RDS Available em us-east-2a + eventos | `prints/08-bonus/13.7-console-rds-eventos-failover.png` |
| 13.3/13.4 atividades do ASG (substituições) | `prints/08-bonus/13.3-13.4-console-asg-atividades.png` |
| Linha do tempo com marcas de cada teste | `prints/08-bonus/bonus-01..06-*.png` (alvos healthy, ALB 5xx, instâncias, tasks, AppErrors, RDS) |

### Estado ao fim do bônus (20:49 UTC)

- chat 4/4 (escalado pelos loops de medição; volta a 2 sozinho), catalog 2/2, worker 1/1, todos na v2; `/health` 200.
- ASG 3 instâncias, todas novas: i-0e0fb3d33369f89f1 (2b), i-036f87b829bab4c7e (2b), i-0b0b2ab08fceab115 (2a).
- RDS Available, primário us-east-2a, standby us-east-2b.
- Policy do chat restaurada (idêntica ao original). DLQ **intocada** (1 mensagem, cc-dlq-not-empty em ALARM).
- Os volumes EBS das 3 instâncias novas nasceram **sem** `project=cc` (o LT não foi alterado, como decidido).

## Ajustes depois do bônus (18/11/2026, 21:00-21:11 UTC)

Autorizados pelo Pedro. Cada mudança foi seguida de `curl /health` (sempre HTTP 200). Evidências em `09-ajustes/`
(estado anterior em `09-ajustes/antes.txt`).

| # | Mudança | Antes | Depois | Por quê | Verificação |
|---|---|---|---|---|---|
| 1 | Tag `project=cc` nos volumes EBS das instâncias novas | 3 volumes sem tag | vol-0bcb9d75…, vol-0641a8b8…, vol-016f1ef5… com `project=cc` | instâncias do refresh/13.4 nasceram com volume sem tag (LT não alterado) | `/health` 200 |
| 2 | Alarme `cc-rds-connections` | > **80** | > **60** (Maximum, 60 s x 2, mesmo SNS) | achado 4: o teto real do db.t4g.micro é ~80 menos os slots reservados; com 80 o alarme nunca dispararia antes do esgotamento (no 13.2 chegamos a 70 e uma task não conectou) | estado OK; `/health` 200 |
| 3 | Alvo do target tracking do chat (`chat-req`) | **50** req/min/task | **600** req/min/task (cooldowns 60/120 iguais) | achado 9: 2 loops de curl (~115 req/min/task) escalavam o chat. Com Bedrock real o turno leva ~2-3 s e o uvicorn tem 40 threads -> saturação ~960 req/min/task; 600 é ~60% disso. A carga do 13.2 (7.000+ req/min/task) continua escalando | AlarmHigh 600 / AlarmLow 540 (recriados pela própria AWS); `/health` 200 |
| 4 | Estratégia de colocação do chat-service | spread AZ + **binpack MEMORY** | spread AZ + **spread instanceId** (+ `--force-new-deployment`); AZ rebalancing segue ENABLED | achado 7: o binpack concentrava as 2 tasks do chat na mesma instância, e a perda dela derrubou o chat ~18 s no 13.4. Escolhido no lugar de `distinctInstance`, que limitaria o chat ao número de instâncias (máx 4 < máx 6 tasks) | deploy estável 21:10:39 sem rollback; **97/97 /health 200** durante o redeploy; tasks em us-east-2a e us-east-2b, em instâncias diferentes |

Catalog-orders-service mantém spread AZ + binpack (não foi pedido). Arquivos: `parte1-build/tt-chat.json` (novo alvo),
`parte1-build/tt-chat-v1-alvo50.json` (original).

## Pendências e próximos passos

- Esvaziar a DLQ depois do vídeo (Pedro).
- Para o futuro: TagSpecifications de `volume` no LT (instâncias novas voltam a nascer com volume sem tag).
- Avaliar o mesmo ajuste de colocação no catalog-orders-service.
- Restringir o `Resource: "*"` do cc-chat-task-role ao ARN do modelo e do perfil de inferência (segurança, nível A) - adiado pelo Pedro.
- Relatório, vídeo e GitHub (próxima conversa).
- Custos que seguem cobrando por hora: NAT, 2 ALBs, RDS Multi-AZ e 3 x t3.medium.
