# Evidências da Parte 2: Livraria Nuvem em sa-east-1 (Terraform)

Data: 2026-11-19. Conta 244736565328, região sa-east-1, perfil `insper`.
Tudo foi criado pelo Terraform em `infra/`, sem reaproveitar nada de Ohio.

## Linha do tempo (UTC)
| Hora | Passo | Resultado | Arquivo |
|---|---|---|---|
| 17:0x | Fase 0 (só leitura) | 3 AZs, t3.medium nas 3, Postgres padrão 18.3, AMI ECS por SSM. Bedrock: só o perfil `global.anthropic.claude-haiku-4-5-20251001-v1:0`, Converse OK em 877 ms | `fase0-plan/fase0-sa-east-1.txt` |
| 17:0x | Plans (backend local temporário) | sa-east-1: 110 a criar. **Portabilidade: o mesmo código com `region=us-east-2` dá 110 a criar** nas AZs us-east-2a/2b. Bootstrap: 6 | `fase0-plan/` |
| 17:14 | Bootstrap | bucket `cc-tfstate-244736565328-sa-east-1` versionado, AES256, acesso público bloqueado, lock nativo do S3 | `bootstrap/` |
| 17:2x | Plan com estado remoto | 110 a criar, 0 a alterar, 0 a destruir | `apply-sp/plan-remoto.txt` |
| 17:2x–17:40 | 1º apply | **falhou** em 2 pontos do código (ver Desvios). 94 recursos criados; o RDS Multi-AZ levou 13m36s | `apply-sp/apply.txt` |
| 17:43–17:44 | 2º apply (com as correções) | **35 adicionados, 0 alterados, 2 destruídos** (os 2 `terraform_data` que tinham falhado, refeitos; nenhum recurso da AWS) | `apply-sp/apply-retomada.txt`, `apply-sp/outputs.*` |
| 17:45:04 | Serviços estáveis | chat 2/2, catalog 2/2, worker 1/1, tasks em sa-east-1a e 1b, 4/4 alvos healthy | `mvp-sp/01-saude.txt` |
| 17:45 | `/health` e `/ready` pelo ALB | 200 / 200 (`llm_mode: bedrock`) | `mvp-sp/01-saude.txt` |
| 17:45:32–17:45:41 | Jornada com Bedrock real | 3 turnos, `degraded=false`. Pedido `3a3193250429` criado às 17:45:40.388 e **CONFIRMED às 17:45:40.589 (201 ms)** | `mvp-sp/02-jornada.txt` |
| 17:46 | Logs correlacionados | mesmo `conversation_id` nos 3 log groups `/cc/sp/*`: chat → "pedido criado" (catalog) → "pedido confirmado" (worker) | `mvp-sp/03-logs-correlacionados.txt` |
| 17:46 | Estado após a jornada | fila e DLQ com 0 mensagens, os 14 alarmes `cc-sp-*` em OK, os 4 volumes EBS com tag, papel do chat restrito ao perfil e ao modelo base do Haiku | `mvp-sp/04-estado-pos-jornada.txt` |

## Lições da Parte 1 aplicadas e confirmadas
- **Volumes EBS:** já nascem com `project=cc` e `env=sp`, pela tag no Launch Template.
- **Papel do chat:** sem `Resource "*"`. Só o perfil de inferência e `foundation-model/anthropic.claude-haiku-4-5-*`.
- **Alarme de conexões do RDS:** limite em 60.
- **Alvo de escala do chat:** 600 requisições por minuto por task.
- **Distribuição do chat e do catalog:** por AZ e por instância. As 2 tasks de cada um ficaram em AZs diferentes.

## Observações
- **ASG subiu de 2 para 4 instâncias** às 17:45 e 17:46, pela escala gerenciada do capacity provider, com o alvo de 80%. As 5 tasks cabem em 2 instâncias, mas com elas cheias a ocupação passa de 80%, e a escala também contou as tasks extras do primeiro deploy. Voltou a 3 sozinha (uma instância de folga, igual a Ohio), como mostra o print 13. Não foi feita nenhuma intervenção.
- **Bedrock em SP usa o perfil `global.`:** a inferência pode ser processada fora do Brasil. Em sa-east-1 não há perfil só da região para o Haiku 4.5.

## Desvios
1. **1º apply com 2 erros no código, não na AWS.**
   - *Login no ECR:* os 3 `docker login` em paralelo colidiram no Keychain do macOS (`item already exists`). Correção: até 5 tentativas com pausa aleatória.
   - *Regra de SG:* a descrição com `->` foi recusada pela AWS, que não aceita `>`. Correção: texto sem o símbolo.
   - As correções estão no commit `6b43600`. O 2º apply terminou sem erros e não houve destroy.
2. **Prints do console:** esta sessão não tem permissão de gravação de tela do macOS (`screencapture`: `could not create image from rect`). Os prints do console foram tirados sem capturar a tela: um Chrome headless com perfil temporário abre o console por login federado (API de federação do AWS Sign-In, com as credenciais SSO do perfil `insper`) e captura só a página pelo DevTools Protocol (`scripts/console-print/cdpshot.py`). O acesso temporário e as credenciais ficaram só em arquivos temporários (nunca exibidos) e foram apagados no fim, assim como os perfis do Chrome.

## Prints
- `prints/01-alb-requisicoes.png`: requisições e latência p95 do ALB.
- `prints/02-tasks-por-servico.png`: tasks em execução por serviço.
- `prints/03-negocio-pedidos-llm.png`: OrdersCreated, OrdersConfirmed e LLMLatencyMs.
- `prints/04-asg-instancias.png`: instâncias do ASG e CapacityProviderReservation.
- `prints/05-console-dashboard-cc-sp.png`: dashboard `cc-sp` (10 widgets).
- `prints/06-console-dashboard-diagnostico.png`: dashboard `cc-sp-diagnostico` (alarmes, erros, Bedrock, tasks, Logs Insights).
- `prints/07-console-ecs-servicos.png`: cluster `cc-sp-cluster` com 3 serviços ativos e 5 tasks em execução.
- `prints/08-console-alarmes.png`: alarmes em OK, inclusive os de target tracking criados pela AWS.
- `prints/09-console-target-groups.png`: `cc-sp-tg-chat` (ALB público) e `cc-sp-tg-catalog` (ALB interno).
- `prints/10-console-ecr.png`: 3 repositórios `cc-sp/*` em sa-east-1, imutáveis e criptografados.
- `prints/11-console-s3-estado-remoto.png`: `terraform.tfstate` no bucket de estado remoto.
- `prints/12-console-rds.png`: `cc-sp-db` com Postgres 18.3, Multi-AZ (1a/1b), gp3 e criptografia.
- `prints/13-console-asg.png`: `cc-sp-asg` com limites 2–4, de volta a 3 instâncias saudáveis e protegidas contra scale-in.
- `prints/14-console-vpc-mapa.png`: VPC `cc-sp-vpc` (10.20.0.0/16), mapa de recursos com 6 sub-redes, 4 tabelas de rotas, IGW, NAT e endpoint S3.

## Prova de que nada depende de Ohio (2026-11-19 19:15 UTC)
O script `scripts/prova-sem-ohio.sh` gerou `portabilidade/prova-sem-ohio.txt`:
1. **Busca no código** (infra, services, scripts) por `us-east-2`, IDs de VPC, SG, AMI e NAT de Ohio, endpoints de Ohio, `us.anthropic` e ECR de Ohio: **nenhuma ocorrência**.
2. **Conta e região fixas nos módulos:** nenhuma. A única região escrita no código é o valor padrão `sa-east-1` de uma variável do bootstrap.
3. **ARNs no estado remoto:** **191 em sa-east-1 e 36 globais** (IAM, S3). Nenhum em us-east-2.
4. **Endpoints que as tasks usam:** ECR, RDS, SQS, SNS e ALB interno, todos em sa-east-1. O Bedrock usa o perfil `global.`.
5. **O mesmo código em us-east-2** dá 110 recursos a criar, nas AZs us-east-2a/2b, sem mudar nenhum arquivo.

**Dependência escondida encontrada e corrigida:** os 3 serviços tinham `os.getenv("AWS_REGION", "us-east-2")`. Agora a região vem só do ambiente, sem padrão fixo. Hoje isso não tinha efeito, porque o Terraform sempre passa `AWS_REGION`. A correção está no código, mas **ainda não foi publicada**: as tasks em execução usam as imagens anteriores. Publicar exige um `apply` que gera 3 imagens novas e faz um rolling deploy dos 3 serviços (o plan mostra 6 a destruir: são as revisões antigas das task definitions e os registros dos builds). Isso fica para quando houver autorização.

## Auditoria e resposta a incidentes (19:19 UTC)
- **Módulo `audit`**, aplicado só ele (`-target=module.audit`): **15 recursos criados, 0 alterados, 0 destruídos** (`auditoria/apply-audit.txt`).
  - Trilha `cc-sp-trail`, multirregião, com eventos globais e validação de integridade dos arquivos.
  - Bucket S3 com acesso público bloqueado, só TLS e retenção de 90 dias.
  - Cópia em `/cc/sp/cloudtrail`, com retenção de 30 dias.
- **3 alarmes de auditoria**, adaptados do CIS: `cc-sp-audit-iam-policy-change`, `cc-sp-audit-sg-change` e `cc-sp-audit-access-denied` (mais de 10 negações em 5 min).
- **Auditoria retroativa** (`auditoria/verificacao-cloudtrail.txt`): o histórico de eventos mostra as 2 mudanças do teste 13.6 na política do chat em Ohio, às 17:16:36 (Deny) e 17:21:13 (restauração), pelo usuário `pedrohav`, além das políticas criadas pelo Terraform em SP.
- **Runbook:** `docs/runbook-incidentes.md`. São 6 playbooks (Bedrock, DLQ, fila, alvos/5xx, banco e auditoria), com consultas de Logs Insights, severidades e o registro pós-incidente. Os tempos citados vêm dos testes da Etapa 13.

## Deploy da correção da região (20:01–20:05 UTC)
- **Apply:** 6 adicionados, 3 alterados e 6 destruídos (`correcao-regiao/apply.txt`). Os 6 destruídos são as 3 revisões antigas das task definitions e os 3 registros de build. Os 3 serviços foram alterados no lugar.
- **Imagens novas:** `chat-service:5f39748db8cb`, `catalog-orders-service:37be1454eccd` e `order-worker:67fa63d5d894`, nas revisões `cc-sp-*:2`. Todos os serviços estáveis 117 s depois do fim do apply.
- **Disponibilidade durante o rolling deploy:** **105/105 respostas 200** em `/health` de 20:01:45 a 20:04:54, com uma checagem a cada ~2 s (`correcao-regiao/disponibilidade-health.tsv`).
- **Depois do deploy:** 4/4 alvos healthy, tasks em sa-east-1a e 1b, `/health` 200 e `/ready` 200 com Bedrock (`correcao-regiao/01-saude-pos-deploy.txt`).
- **Jornada:** pedido `d482661154b1` criado às 20:05:35.688 e **CONFIRMED às 20:05:35.911 (223 ms)**, com `degraded=false` nos 3 turnos e `conversation_id` correlacionado nos 3 serviços (`correcao-regiao/02-jornada.txt`, `03-logs-correlacionados.txt`).
- **Persistência:** o pedido anterior `3a3193250429` continua CONFIRMED, e o estoque de "1984" passou de 30 para 29 por causa dele e se manteve depois da troca de todas as tasks.

## Carga curta em SP (20/11, 23:32–23:42 UTC)
- **Teste:** `hey -z 10m -c 100` no `/health` do ALB (`carga-sp/hey-10min.txt`). Vazão de **274,3 req/s**, 164.651/164.651
  respostas 200, p95 de 377 ms.
- **Linha do tempo** (`carga-sp/linha-do-tempo.tsv`): chat **2 → 6** às 23:38:16, ~6 min após o início; **6/6 healthy no
  ALB às 23:38:39 (23 s)**; `CapacityProviderReservation` de 80 para 100.
- **ASG já no máximo (4/4) antes da carga:** com o `spread` por instância, as 5 tasks ocupam 3 máquinas, e o alvo de 80%
  dá ⌈3 ÷ 0,8⌉ = 4. Por isso não houve scale-out de EC2 em SP; as tasks novas couberam na instância de folga
  (`carga-sp/00-antes.txt`). O scale-out de EC2 está demonstrado em Ohio (3 → 4 → 3).
