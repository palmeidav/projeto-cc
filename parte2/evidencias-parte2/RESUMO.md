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
