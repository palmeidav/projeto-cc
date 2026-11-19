"""Diagrama da arquitetura da Livraria Nuvem em sa-east-1 (Parte 2, Terraform).

Gera docs/diagrama-arquitetura.png (16:9) com a biblioteca "diagrams" (icones oficiais da AWS).
Nomes e numeros conferidos contra infra/ e contra a conta (2026-11-19):
  VPC 10.20.0.0/16 (var.vpc_cidr) | sub-redes /24: publicas .1/.2, aplicacao .11/.12, dados .21/.22
  ASG cc-sp-asg min 2 / max 4 (t3.medium) | capacity provider cc-sp-cp alvo 80%
  chat 2-6 tasks (:8000) | catalog 2-6 (:8001) | worker 1-5 | RDS PostgreSQL 18.3 db.t4g.micro Multi-AZ 1a/1b
  SQS cc-sp-orders (visibilidade 60 s, maxReceiveCount 3) -> cc-sp-orders-dlq | SNS cc-sp-order-events

Rodar (sem instalar nada no Mac): bash docs/gerar-diagrama.sh
As setas vermelhas numeradas 1..8 seguem o caminho de um pedido; as cinzas tracejadas sao fluxos auxiliares.
Ajustes comuns: textos nos rotulos abaixo; tamanho das fontes em FS_*; espacamento em graph_attr.
"""
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECR, EC2AutoScaling, ElasticContainerServiceService
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.integration import SimpleNotificationServiceSns, SimpleQueueServiceSqs
from diagrams.aws.management import Cloudtrail, Cloudwatch
from diagrams.aws.ml import Bedrock
from diagrams.aws.network import ElbApplicationLoadBalancer, InternetGateway, NATGateway
from diagrams.aws.security import IAM, SecretsManager
from diagrams.onprem.client import Users

FONT = "DejaVu Sans"
FS_TITLE, FS_CLUSTER, FS_NODE, FS_STEP, FS_AUX = "40", "24", "22", "30", "19"
PATH = "#C7254E"   # caminho do pedido
AUX = "#666666"    # fluxos auxiliares

graph_attr = {
    "fontname": FONT, "fontsize": FS_TITLE, "labelloc": "t", "pad": "0.5",
    "nodesep": "0.45", "ranksep": "1.15", "splines": "spline", "newrank": "true",
    "dpi": "110", "bgcolor": "white",
}
node_attr = {"fontname": FONT, "fontsize": FS_NODE, "imagescale": "true"}
edge_attr = {"fontname": FONT, "penwidth": "2.0", "arrowsize": "1.3"}


def alto(cls, rotulo, **kw):
    """Cria o no com altura suficiente para o rotulo nao encostar no icone."""
    linhas = rotulo.count("\n") + 1
    return cls(rotulo, height=str(2.0 + 0.42 * linhas), **kw)


def passo(n, texto=""):
    return Edge(label=f" {n} {texto}".rstrip(), color=PATH, fontcolor=PATH,
                penwidth="4", fontsize=FS_STEP, fontname=f"{FONT} Bold")


def segue():
    return Edge(color=PATH, penwidth="4")


def aux(texto=""):
    return Edge(label=texto, color=AUX, fontcolor=AUX, style="dashed", fontsize=FS_AUX, constraint="false")


def invis():
    return Edge(style="invis")


def caixa(cor, **extra):
    return {"bgcolor": cor, "fontsize": FS_CLUSTER, "fontname": FONT, "style": "rounded",
            "margin": "18", "labeljust": "l", **extra}


with Diagram(
    "Livraria Nuvem: comércio conversacional na AWS · sa-east-1 (Terraform)",
    filename="docs/diagrama-arquitetura", outformat="png", show=False, direction="LR",
    graph_attr=graph_attr, node_attr=node_attr, edge_attr=edge_attr,
):
    cliente = alto(Users, "Cliente")

    with Cluster("AWS · South America (São Paulo)", graph_attr=caixa("#FAFAFA")):
        igw = alto(InternetGateway, "Internet\nGateway")

        with Cluster("VPC cc-sp-vpc · 10.20.0.0/16 · 2 AZs (sa-east-1a, sa-east-1b)", graph_attr=caixa("#EEF4FB")):
            with Cluster("Públicas\n10.20.1.0/24\n10.20.2.0/24", graph_attr=caixa("#DFF0DF")):
                alb = alto(ElbApplicationLoadBalancer, "ALB público\nHTTP 80")
                nat = alto(NATGateway, "NAT\nGateway")

            with Cluster("Aplicação (privadas) · 10.20.11.0/24 · 10.20.12.0/24\n"
                         "ECS sobre EC2 · ASG t3.medium mín 2 / máx 4 + Capacity Provider (alvo 80%)",
                         graph_attr=caixa("#E6ECF7", labelloc="b")):
                chat = alto(ElasticContainerServiceService, "chat-service\n:8000 · 2–6 tasks")
                ilb = alto(ElbApplicationLoadBalancer, "ALB interno\nHTTP 80")
                catalog = alto(ElasticContainerServiceService, "catalog-orders\n-service\n:8001 · 2–6 tasks")
                worker = alto(ElasticContainerServiceService, "order-worker\n1–5 tasks")
                asg = alto(EC2AutoScaling, "ASG +\nCapacity\nProvider")

            with Cluster("Dados (sem internet)\n10.20.21.0/24 · 10.20.22.0/24", graph_attr=caixa("#FBEEDF")):
                rds = RDSPostgresqlInstance("RDS PostgreSQL 18.3\nMulti-AZ\nprimário 1a · standby 1b", height="3.9")

        with Cluster("Serviços regionais", graph_attr=caixa("#FFFFFF")):
            ecr = alto(ECR, "ECR\n3 repositórios")
            bedrock = alto(Bedrock, "Bedrock\nClaude Haiku 4.5")
            sqs = alto(SimpleQueueServiceSqs, "SQS\ncc-sp-orders")
            dlq = alto(SimpleQueueServiceSqs, "DLQ\n(3 falhas)")
            sns = alto(SimpleNotificationServiceSns, "SNS\nevento")

        with Cluster("Segurança e operação", graph_attr=caixa("#F1ECF8", rank="same")):
            secrets = alto(SecretsManager, "Secrets Manager\nsenha do RDS")
            iam = alto(IAM, "IAM · 5 papéis\nmenor privilégio")
            cw = alto(Cloudwatch, "CloudWatch\nlogs · 14 alarmes")
            trail = alto(Cloudtrail, "CloudTrail\nmultirregião")

    # ---- caminho de um pedido (1..8) ----
    cliente >> passo(1) >> igw >> segue() >> alb
    alb >> passo(2) >> chat
    chat >> passo(3) >> nat >> segue() >> bedrock
    chat >> passo(4) >> ilb
    ilb >> passo(5) >> catalog
    catalog >> passo(6) >> rds
    catalog >> passo(7) >> sqs
    sqs >> passo(8) >> worker

    # ---- fluxos auxiliares (não mexem no layout) ----
    worker >> aux("confirma") >> rds
    worker >> aux("publica") >> sns
    sqs >> aux() >> dlq

    # ---- posicionamento (invisível) ----
    igw >> invis() >> ecr                       # ECR embaixo, no início da faixa regional
    chat >> invis() >> asg                      # ASG dentro do cluster, perto do chat
    sqs >> invis() >> dlq
    worker >> invis() >> sns
    sns >> invis() >> secrets                   # faixa de segurança como última coluna (lateral direita)
    secrets >> invis() >> iam
    iam >> invis() >> cw
    cw >> invis() >> trail
