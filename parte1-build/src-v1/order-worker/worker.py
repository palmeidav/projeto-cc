"""order-worker: consome a fila SQS, confirma o pedido (idempotente) e publica o evento no SNS."""
import json
import logging
import os
import signal
import time

import boto3
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from logsetup import emf, log, setup

setup()

REGION = os.getenv("AWS_REGION", "us-east-2")
QUEUE_URL = os.environ["QUEUE_URL"]
TOPIC_ARN = os.getenv("TOPIC_ARN", "")
DELAY = float(os.getenv("PROCESS_DELAY_SECONDS", "0"))  # simula processamento lento (teste de carga)

sqs = boto3.client("sqs", region_name=REGION)
sns = boto3.client("sns", region_name=REGION) if TOPIC_ARN else None
pool = ConnectionPool(
    make_conninfo(host=os.environ["DB_HOST"], port=os.getenv("DB_PORT", "5432"),
                  dbname=os.getenv("DB_NAME", "shop"), user=os.environ["DB_USER"],
                  password=os.environ["DB_PASSWORD"], connect_timeout="5",
                  sslmode=os.getenv("DB_SSLMODE", "prefer")),
    min_size=1, max_size=3, kwargs={"row_factory": dict_row},
    check=ConnectionPool.check_connection, open=False)

running = True


def _stop(signum, frame):
    global running
    running = False
    log(logging.INFO, "sinal de parada recebido; finalizando após o lote atual")


signal.signal(signal.SIGTERM, _stop)
signal.signal(signal.SIGINT, _stop)


def heartbeat():
    """Arquivo usado pelo health check do ECS."""
    with open("/tmp/heartbeat", "w") as f:
        f.write(str(time.time()))


def process(body: str) -> bool:
    """Confirma o pedido. Devolve False se já estava confirmado (duplicidade). Lança exceção se inválida."""
    data = json.loads(body)          # JSON inválido -> exceção -> tentativas -> DLQ
    order_id = data["order_id"]      # campo ausente -> exceção -> DLQ
    with pool.connection(timeout=10) as conn:
        row = conn.execute("SELECT status FROM orders WHERE id = %s FOR UPDATE", (order_id,)).fetchone()
        if row is None:
            raise LookupError(f"pedido {order_id} não existe")
        if row["status"] == "CONFIRMED":
            return False
        if DELAY:
            time.sleep(DELAY)
        conn.execute("UPDATE orders SET status = 'CONFIRMED', confirmed_at = now() WHERE id = %s", (order_id,))
        if sns:  # publicado antes do commit: se falhar, tudo é refeito (entrega pelo menos uma vez)
            sns.publish(TopicArn=TOPIC_ARN, Subject="Pedido confirmado",
                        Message=json.dumps({"event": "order_confirmed", "order_id": order_id}))
    return True


def main():
    pool.open(wait=False)
    log(logging.INFO, "worker iniciado", fila=QUEUE_URL)
    while running:
        heartbeat()
        try:
            resp = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=10, WaitTimeSeconds=10,
                                       AttributeNames=["ApproximateReceiveCount"])
        except Exception as e:
            log(logging.ERROR, "falha ao ler a fila", erro=str(e)[:300])
            time.sleep(5)
            continue
        for m in resp.get("Messages", []):
            attempts = m.get("Attributes", {}).get("ApproximateReceiveCount")
            try:
                done = process(m["Body"])
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=m["ReceiptHandle"])
                if done:
                    emf("OrdersConfirmed", 1)
                    log(logging.INFO, "pedido confirmado", message_id=m["MessageId"])
                else:
                    log(logging.INFO, "mensagem duplicada ignorada", message_id=m["MessageId"])
            except Exception as e:
                # não apaga: volta à fila após o visibility timeout; na 3ª tentativa vai para a DLQ
                emf("OrderProcessingFailures", 1)
                log(logging.ERROR, "falha ao processar mensagem", message_id=m["MessageId"],
                    tentativa=attempts, erro=repr(e)[:300])
    pool.close()
    log(logging.INFO, "worker finalizado")


if __name__ == "__main__":
    main()
