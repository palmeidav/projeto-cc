Etapa 13 do projeto CC
Projeto Livraria Nuvem - nível B (+bônus A)

Versão final do etapa13.md, revisada contra o roteiro, o guia, o enunciado e a demonstração. Como usar: 1) salva o texto abaixo como etapa13.md na pasta projeto-cc, junto com o conteúdo do zip e os 4 PDFs; 2) opcional: renomeia pra CLAUDE.md, que o Claude Code carrega automático em toda sessão dessa pasta (troca o conteúdo quando for pro Terraform); 3) abre a pasta no Claude Code e manda só: Leia o etapa13.md e os PDFs desta pasta e siga o etapa13.md passo a passo.

Salva como etapa13.md
# Etapa 13 do projeto CC - Livraria Nuvem (nível B + bônus A)

## Contexto

Projeto semestral de Computação em Nuvem (Insper): a "Livraria Nuvem", uma loja com vendedor de IA rodando em 3 serviços ECS na AWS. Nesta pasta estão o enunciado, o roteiro da Parte 1 (roteiro_parte1_aws_ohio), o guia do que já foi feito (guia_projeto_cc_parte1), a demonstração do MVP (demonstracao_nivel_B_MVP) e o código dos 3 serviços. Leia os PDFs antes de começar.

A Parte 1 já está montada à mão em Ohio (us-east-2) pela minha colega Ana Clara. Meu trabalho agora é rodar os testes da Etapa 13 do roteiro dela que fecham o nível B da rubrica, com as evidências. Se sobrar tempo, tem uma seção bônus no final com os testes que miram o nível A. Estou num Mac com Apple Silicon.

## Sequência principal (fecha o B)

### 1. Setup do acesso AWS

Confere se tenho AWS CLI v2 (`aws --version`). Se não tiver, instala com `brew install awscli`. Instala também `jq` e `hey` via brew se faltarem. Confere se o Docker Desktop está instalado e rodando (vai ser usado no passo 4); se não estiver, me avisa para eu instalar.

ANTES de configurar o SSO: me pede para abrir o portal https://d-9067f848eb.awsapps.com/start/, entrar com meu usuário (pedrohav) e clicar em "Access keys". A região que aparece nessa tela é a região do SSO. Me pergunta qual é e usa ESSA região no passo seguinte.

Configura o SSO com `aws configure sso`:

- Start URL: https://d-9067f848eb.awsapps.com/start/
- Região do SSO: a que eu li na tela "Access keys" (NÃO assume us-east-2 aqui)
- Conta: 244736565328
- Nome do profile: insper
- Região default dos comandos: us-east-2

Roda `aws sso login --profile insper`. Espera eu confirmar que o login passou.

Confirma a identidade com `aws sts get-caller-identity --profile insper`.

Daqui para frente, `export AWS_PROFILE=insper` e região us-east-2 em tudo.

### 2. Portão de segurança: o cc-cluster existe?

```
aws ecs describe-clusters --clusters cc-cluster --region us-east-2
aws resourcegroupstaggingapi get-resources --tag-filters Key=project,Values=cc --output table --region us-east-2
```

SE O CLUSTER NÃO EXISTIR (ou não houver recursos com a tag): PARA TUDO. Não cria nada. Me avisa que preciso falar com a Ana Clara, porque o projeto pode estar numa conta pessoal dela.

### 3. Evidências do estado ANTES

Monta a pasta `evidencias-etapa13/` e guarda nela, em texto e com horário de cada comando:

- Estado dos serviços: `aws ecs describe-services --cluster cc-cluster --services chat-service catalog-orders-service order-worker` (referência: chat 2/2, catalog 2/2, worker 1/1)
- Target groups cc-tg-chat e cc-tg-catalog com `aws elbv2 describe-target-health` (esperado: 2 alvos healthy em cada, em instâncias diferentes)
- Launch Template cc-lt, ASG cc-asg (min 2, desejado 2, max 4) e Capacity Provider cc-cp (alvo 80%). ATENÇÃO: o guia registra que o CP subiu o ASG de 2 para 3 instâncias em 24/10 e a terceira ficou ociosa (0 tasks) sem ser removida. Anota quantas instâncias existem AGORA e se essa terceira ainda está lá - ela cobra por hora e é ponto aberto do guia.
- DNS do ALB público (ALB_DNS), do ALB interno (ILB_DNS) e URLs das filas (Q_URL da cc-orders, DLQ_URL da cc-orders-dlq), recuperados com `aws elbv2 describe-load-balancers` e `aws sqs get-queue-url` (não há env.sh)
- `curl http://$ALB_DNS/health` devolvendo 200
- Me orienta a tirar os prints do console: target groups healthy, Launch Template + Capacity Provider, e o dashboard cc no CloudWatch

### 4. Logs correlacionáveis (correção de código + Logs Insights)

Hoje o conversation_id NÃO atravessa os serviços: o chat só loga em erros, o catalog não recebe, e o worker loga só message_id. Faz a menor mudança possível no código:

- chat-service: logar conversation_id em todo turno (não só em erro) e enviar o header X-Conversation-Id ao chamar POST /orders do catalog
- catalog-orders-service: ler esse header, incluir conversation_id no log "pedido criado" e no payload da mensagem do outbox
- order-worker: incluir order_id e conversation_id (se vier na mensagem) no log "pedido confirmado"

Me mostra o diff antes de buildar e espera meu "pode ir". Depois: `docker build --platform linux/amd64`, push com tag v2 no ECR de Ohio (cc/chat-service, cc/catalog-orders-service, cc/order-worker), nova revisão das 3 task definitions mudando SÓ a imagem para v2, e update-service. O circuit breaker com rollback protege se algo der errado. Espera estabilizar e confere /health 200.

Aí: faz uma conversa nova até fechar um pedido pelo POST http://$ALB_DNS/chat e mostra no CloudWatch Logs Insights (os 3 log groups /cc/chat-service, /cc/catalog-orders-service, /cc/order-worker juntos) a mesma conversation_id aparecendo no chat, no catalog e no worker. Guarda a consulta e o resultado, e me orienta no print.

### 5. Teste 13.5 - Mensagem venenosa (DLQ) e duplicidade

```
aws sqs send-message --queue-url $Q_URL --message-body 'poison'
# aguardar ~3 minutos; a fila tem visibilidade de 60s e maxReceiveCount 3
aws sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names ApproximateNumberOfMessages
```

Confirma que a mensagem chegou na cc-orders-dlq e que o alarme cc-dlq-not-empty disparou (avisa o tópico SNS cc-alarms).

Duplicidade: manda o mesmo POST /orders duas vezes com o mesmo header Idempotency-Key e comprova que existe um único pedido. O catalog-orders-service só é alcançável pelo ALB INTERNO. NÃO usa `aws ecs execute-command` (o serviço não tem enableExecuteCommand e a task role não tem SSM). Usa o caminho do passo 7 do PDF de demonstração: `aws ssm send-command` numa instância do cluster, chamando o ALB interno. Pega um ID atual com:

```
aws ssm describe-instance-information --query 'InstanceInformationList[].InstanceId' --output text
```

Como o body do pedido é JSON (formato `{"customer_name": "...", "items": [...]}`, confere o modelo OrderIn no código), monta o parâmetro do send-command num arquivo e usa `--parameters file://params.json`, para não quebrar as aspas. Roda DUAS vezes com a mesma Idempotency-Key e lista os pedidos (`curl -s http://$ILB_DNS/orders` pelo mesmo caminho SSM) para comprovar que existe um só. O log "pedido repetido (idempotência)" do catalog também serve de evidência.

Depois reenvia ao SQS uma mensagem de um pedido já confirmado (mesmo formato que o outbox usa) e comprova que o worker não processa duas vezes (log "mensagem duplicada ignorada" + pedido continua único no banco).

### 6. Teste 13.2 - Elasticidade sob carga

ATENÇÃO: esse teste escala instâncias EC2, que cobram por hora. ME PEDE UM "PODE IR" EXPLÍCITO ANTES DE COMEÇAR.

Preparação (evita custo e limite do Bedrock):

- Registra uma nova revisão da task definition do chat-service (a da v2) com LLM_MODE=mock, mudando só esse env
- update-service para essa revisão e espera estabilizar

Teste (comando do roteiro):

```
hey -z 5m -c 80 -m POST -H 'Content-Type: application/json' -d '{"message":"oi"}' http://$ALB_DNS/chat
```

Durante o teste, anota com horários: requisições/s e latência; tasks do chat-service subindo (ALBRequestCountPerTarget, alvo 50, min 2 max 6); tasks em PROVISIONING quando faltar espaço; instâncias do ASG passando de 2 para 3 ou 4 (Capacity Provider, alvo 80%; se a 3ª instância ociosa do guia ainda existir, o ponto de partida real é 3). Aproveita e registra o comportamento da métrica CapacityProviderReservation - o guia marcou isso como ponto aberto para observar neste teste. Anota também o tempo até a nova task ficar healthy e até a nova instância entrar no cluster. Depois, acompanha o scale-in (uns 15 minutos). Me orienta nos prints do dashboard durante o pico e depois da volta.

DEPOIS: volta o chat-service para a revisão v2 com o Bedrock real e confirma que estabilizou. Faz um teste curto com poucas requisições no modo real e registra a latência (métrica CC/LLMLatencyMs).

### 7. Fechamento: volta ao estado normal

Confere e registra:

- ASG de volta ao desejado 2 (mín 2, máx 4). Se a terceira instância ociosa continuar lá depois do scale-in, registra no RESUMO e decide comigo antes de encerrar - ela cobra por hora.
- Serviços estáveis: chat-service na revisão v2 com Bedrock real; chat 2/2, catalog 2/2, worker 1/1
- `curl http://$ALB_DNS/health` devolvendo 200
- Nenhum recurso criado fora da tag project=cc

Se algo não tiver voltado ao normal, resolve comigo antes de fechar.

### 8. Resumo consolidado

Gera `evidencias-etapa13/RESUMO.md` e me cola o conteúdo, com:

- Cada teste: PASSOU ou FALHOU
- Números principais: requisições/s e latência da carga, tasks e instâncias antes/pico/depois, tempos de scale-out e scale-in, mensagens na DLQ, horários
- O caminho de cada print (pasta organizada por teste)
- A mudança de código do passo 4 (o que mudou e por quê) e a nova tag v2 das imagens
- A confirmação do passo 7
- Desvios do roteiro da Ana Clara e por quê

## BÔNUS NÍVEL A - só se sobrar tempo

Só entra aqui se eu disser "bora o bônus" depois do RESUMO. Registra antes/durante/depois com horários e atualiza o RESUMO.md.

### 13.1 - Substituição de uma task sem indisponibilidade

Terminal 1 (deve imprimir só 200):

```
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://$ALB_DNS/health; sleep 0.5; done
```

Terminal 2:

```
T=$(aws ecs list-tasks --cluster cc-cluster --service-name chat-service --query 'taskArns[0]' --output text)
aws ecs stop-task --cluster cc-cluster --task $T
```

### 13.6 - Falha do LLM

Salva a policy atual antes:

```
aws iam get-role-policy --role-name cc-chat-task-role --policy-name inline --query PolicyDocument --output json > p-chat.json
aws iam delete-role-policy --role-name cc-chat-task-role --policy-name inline
```

Conversa com o vendedor: deve responder com mensagem amigável e NÃO criar pedido. DEIXA A FALHA ATIVA e emenda no 13.8. Só restaura depois:

```
aws iam put-role-policy --role-name cc-chat-task-role --policy-name inline --policy-document file://p-chat.json
```

### 13.8 - Diagnóstico pela observabilidade

Com a falha do 13.6 ativa, mostra que dá para localizar a falha olhando só o dashboard cc, os alarmes e o Logs Insights por conversation_id. Depois restaura a policy e confirma que o vendedor voltou.

### 13.3 e 13.4 - Vida e morte das instâncias

ME PEDE UM "PODE IR" ANTES. Deixa o loop do 13.1 rodando.

No 13.3, o ASG tem scale-in protection e o Capacity Provider protege instâncias com tasks, então o instance refresh padrão espera até 1h e falha. Acrescenta `"ScaleInProtectedInstances":"Refresh"` e registra o desvio no RESUMO.

```
CI=$(aws ecs list-container-instances --cluster cc-cluster --query 'containerInstanceArns[0]' --output text)
aws ecs update-container-instances-state --cluster cc-cluster --container-instances $CI --status DRAINING
aws autoscaling start-instance-refresh --auto-scaling-group-name cc-asg \
--preferences '{"MinHealthyPercentage":50,"InstanceWarmup":120,"ScaleInProtectedInstances":"Refresh"}'
```

13.4:

```
aws ec2 terminate-instances --instance-ids <ID_DA_INSTANCIA>
```

Consulta os pedidos (via SSM no ALB interno) antes e depois para mostrar que os dados continuam no RDS. Anota os tempos.

### 13.7 - Falha do banco

ME PEDE UM "PODE IR" ANTES.

```
aws rds reboot-db-instance --db-instance-identifier cc-db --force-failover
```

Mostra que a aplicação volta (/health e uma conversa nova) e que os pedidos anteriores continuam lá. Anota os tempos.

## Regras fixas

- Nunca imprime segredos (senha do banco, tokens, chaves). Mascara se algum comando for mostrar.
- Me pede confirmação antes de APAGAR qualquer coisa e antes de criar recurso que cobra por hora.
- Usa os comandos do roteiro da Ana Clara. Desvios esperados: a correção de logs com imagens v2 (passo 4), o caminho via SSM e o arquivo de parâmetros (13.5) e o `"ScaleInProtectedInstances":"Refresh"` (13.3). Todos registrados no RESUMO.
- Comandos, saídas e horários vão para evidencias-etapa13/. Os prints do console eu tiro com tua orientação (qual tela, o que tem que estar visível e quando).
- Não junta tudo num script gigante: comando por comando, conferindo comigo. A Parte 1 tem que ficar claramente "manual por CLI".
- Se algo sair do previsto (serviço não escala, alarme não dispara, DLQ vazia), para e me mostra o estado em vez de sair remediando.
- Todo docker build usa --platform linux/amd64.

Escopo de hoje: a sequência principal (B) e, se eu pedir, o bônus (A). Nada de Terraform e nada de recriar a infra.
Nada aqui executa nada - é só o texto do etapa13.md.
