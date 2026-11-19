"""catalog-orders-service: catálogo, estoque e pedidos (PostgreSQL) + publicação no SQS via outbox."""
import json
import logging
import os
import threading
import time
import uuid
from collections import defaultdict
from contextlib import asynccontextmanager
from typing import Optional

import boto3
import psycopg
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field

from logsetup import emf, log, setup

setup()

REGION = os.getenv("AWS_REGION", "us-east-2")
QUEUE_URL = os.getenv("QUEUE_URL", "")

conninfo = make_conninfo(
    host=os.environ["DB_HOST"],
    port=os.getenv("DB_PORT", "5432"),
    dbname=os.getenv("DB_NAME", "shop"),
    user=os.environ["DB_USER"],
    password=os.environ["DB_PASSWORD"],
    connect_timeout="5",
    sslmode=os.getenv("DB_SSLMODE", "prefer"),
)
pool = ConnectionPool(
    conninfo, min_size=1, max_size=int(os.getenv("DB_POOL_MAX", "10")),
    kwargs={"row_factory": dict_row}, check=ConnectionPool.check_connection, open=False,
)

SCHEMA = """
CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, category TEXT,
  price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
  stock INTEGER NOT NULL CHECK (stock >= 0));
CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY, idempotency_key TEXT UNIQUE NOT NULL, customer_name TEXT NOT NULL,
  total_cents INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'PENDING',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), confirmed_at TIMESTAMPTZ);
CREATE TABLE IF NOT EXISTS order_items (
  order_id TEXT NOT NULL REFERENCES orders(id), product_id INTEGER NOT NULL REFERENCES products(id),
  quantity INTEGER NOT NULL CHECK (quantity > 0), unit_price_cents INTEGER NOT NULL,
  PRIMARY KEY (order_id, product_id));
CREATE TABLE IF NOT EXISTS outbox (
  id BIGSERIAL PRIMARY KEY, order_id TEXT NOT NULL, payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), sent_at TIMESTAMPTZ);
CREATE INDEX IF NOT EXISTS outbox_unsent ON outbox (id) WHERE sent_at IS NULL;
"""

SEED = [
    ("Dom Casmurro", "Machado de Assis", "Romance", 3990, 25),
    ("Memórias Póstumas de Brás Cubas", "Machado de Assis", "Romance", 3490, 18),
    ("Grande Sertão: Veredas", "João Guimarães Rosa", "Romance", 6490, 8),
    ("Capitães da Areia", "Jorge Amado", "Romance", 4290, 20),
    ("A Hora da Estrela", "Clarice Lispector", "Romance", 3290, 15),
    ("Vidas Secas", "Graciliano Ramos", "Romance", 3190, 22),
    ("O Cortiço", "Aluísio Azevedo", "Romance", 2990, 12),
    ("O Pequeno Príncipe", "Antoine de Saint-Exupéry", "Infantil", 2790, 40),
    ("1984", "George Orwell", "Ficção científica", 4590, 30),
    ("Sapiens", "Yuval Noah Harari", "História", 6990, 10),
    ("Código Limpo", "Robert C. Martin", "Tecnologia", 8990, 5),
    ("Fahrenheit 451", "Ray Bradbury", "Ficção científica", 3890, 0),
]


def init_db():
    """Cria tabelas e dados de exemplo (idempotente; o advisory lock evita corrida entre réplicas)."""
    for attempt in range(1, 31):
        try:
            with pool.connection(timeout=10) as conn:
                conn.execute("SELECT pg_advisory_xact_lock(42)")
                conn.execute(SCHEMA)
                if conn.execute("SELECT count(*) AS n FROM products").fetchone()["n"] == 0:
                    with conn.cursor() as cur:
                        cur.executemany(
                            "INSERT INTO products (title, author, category, price_cents, stock) "
                            "VALUES (%s, %s, %s, %s, %s)", SEED)
                    log(logging.INFO, "catálogo inicial criado", produtos=len(SEED))
            return
        except Exception as e:  # banco ainda subindo
            log(logging.WARNING, "aguardando o banco", tentativa=attempt, erro=str(e)[:200])
            time.sleep(2)
    raise RuntimeError("banco indisponível na inicialização")


stop_event = threading.Event()


def outbox_relay():
    """Envia ao SQS as mensagens gravadas na mesma transação do pedido (nenhum pedido fica sem mensagem)."""
    if not QUEUE_URL:
        log(logging.WARNING, "QUEUE_URL vazio: relay do outbox desativado")
        return
    sqs = boto3.client("sqs", region_name=REGION)
    last_gauge = 0.0
    while not stop_event.is_set():
        sent = 0
        try:
            with pool.connection(timeout=10) as conn:
                rows = conn.execute(
                    "SELECT id, order_id, payload FROM outbox WHERE sent_at IS NULL "
                    "ORDER BY id LIMIT 10 FOR UPDATE SKIP LOCKED").fetchall()
                for r in rows:
                    sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(r["payload"]))
                    conn.execute("UPDATE outbox SET sent_at = now() WHERE id = %s", (r["id"],))
                    sent += 1
                    log(logging.INFO, "mensagem enviada ao SQS", order_id=r["order_id"])
            if time.time() - last_gauge > 30:
                with pool.connection(timeout=10) as conn:
                    n = conn.execute("SELECT count(*) AS n FROM outbox WHERE sent_at IS NULL").fetchone()["n"]
                emf("OutboxPending", n)
                last_gauge = time.time()
        except Exception as e:
            log(logging.ERROR, "falha no relay do outbox", erro=str(e)[:300])
        stop_event.wait(0.2 if sent else 1.0)


@asynccontextmanager
async def lifespan(app):
    pool.open(wait=False)
    init_db()
    t = threading.Thread(target=outbox_relay, daemon=True)
    t.start()
    yield
    stop_event.set()
    pool.close()


app = FastAPI(title="catalog-orders-service", lifespan=lifespan)


@app.middleware("http")
async def request_log(request: Request, call_next):
    cid = request.headers.get("x-correlation-id") or uuid.uuid4().hex
    start = time.time()
    response = await call_next(request)
    response.headers["X-Correlation-ID"] = cid
    if request.url.path != "/health":
        log(logging.INFO, "request", method=request.method, path=request.url.path,
            status=response.status_code, ms=int((time.time() - start) * 1000), correlation_id=cid)
    return response


@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception):
    log(logging.ERROR, "erro não tratado", path=request.url.path, erro=repr(exc)[:300])
    return JSONResponse(status_code=500, content={"detail": "erro interno"})


# ------------------------------------------------------------------ saúde
@app.get("/health")
def health():
    """Liveness: não depende do banco (uma falha do banco não deve derrubar as tasks)."""
    return {"status": "ok"}


@app.get("/ready")
def ready():
    try:
        with pool.connection(timeout=3) as conn:
            conn.execute("SELECT 1")
        return {"status": "ready"}
    except Exception:
        return JSONResponse(status_code=503, content={"status": "db indisponível"})


# ------------------------------------------------------------------ catálogo
def product_view(r):
    return {"product_id": r["id"], "title": r["title"], "author": r["author"],
            "category": r["category"], "price_cents": r["price_cents"],
            "price_brl": f"{r['price_cents'] / 100:.2f}", "stock": r["stock"]}


@app.get("/products")
def list_products(q: Optional[str] = None, limit: int = 20):
    limit = max(1, min(limit, 50))
    with pool.connection(timeout=5) as conn:
        if q and q.strip():
            like = f"%{q.strip()}%"
            rows = conn.execute(
                "SELECT * FROM products WHERE title ILIKE %s OR author ILIKE %s OR category ILIKE %s "
                "ORDER BY title LIMIT %s", (like, like, like, limit)).fetchall()
        else:
            rows = conn.execute("SELECT * FROM products ORDER BY title LIMIT %s", (limit,)).fetchall()
    return [product_view(r) for r in rows]


@app.get("/products/{product_id}")
def get_product(product_id: int):
    with pool.connection(timeout=5) as conn:
        r = conn.execute("SELECT * FROM products WHERE id = %s", (product_id,)).fetchone()
    if not r:
        raise HTTPException(404, "produto não encontrado")
    return product_view(r)


@app.get("/products/{product_id}/stock")
def get_stock(product_id: int):
    p = get_product(product_id)
    return {"product_id": p["product_id"], "title": p["title"], "stock": p["stock"]}


# ------------------------------------------------------------------ pedidos
class Item(BaseModel):
    product_id: int
    quantity: int = Field(gt=0, le=20)


class OrderIn(BaseModel):
    customer_name: str = Field(min_length=1, max_length=100)
    items: list[Item] = Field(min_length=1, max_length=10)


def load_order(conn, order_id):
    o = conn.execute("SELECT * FROM orders WHERE id = %s", (order_id,)).fetchone()
    if not o:
        return None
    items = conn.execute(
        "SELECT i.product_id, p.title, i.quantity, i.unit_price_cents FROM order_items i "
        "JOIN products p ON p.id = i.product_id WHERE i.order_id = %s ORDER BY i.product_id",
        (order_id,)).fetchall()
    return {"order_id": o["id"], "status": o["status"], "customer_name": o["customer_name"],
            "total_cents": o["total_cents"], "total_brl": f"{o['total_cents'] / 100:.2f}",
            "created_at": o["created_at"].isoformat(),
            "confirmed_at": o["confirmed_at"].isoformat() if o["confirmed_at"] else None,
            "items": items}


def replay(key):
    with pool.connection(timeout=5) as conn:
        row = conn.execute("SELECT id FROM orders WHERE idempotency_key = %s", (key,)).fetchone()
        return load_order(conn, row["id"]) if row else None


@app.post("/orders")
def create_order(body: OrderIn, idempotency_key: Optional[str] = Header(default=None),
                 x_conversation_id: Optional[str] = Header(default=None)):
    if not idempotency_key:
        raise HTTPException(400, "header Idempotency-Key é obrigatório")

    existing = replay(idempotency_key)
    if existing:
        log(logging.INFO, "pedido repetido (idempotência)", order_id=existing["order_id"],
            conversation_id=x_conversation_id)
        return JSONResponse(status_code=200, content={**existing, "idempotent_replay": True})

    wanted = defaultdict(int)
    for it in body.items:
        wanted[it.product_id] += it.quantity
    order_id = uuid.uuid4().hex[:12]
    try:
        with pool.connection(timeout=10) as conn:
            rows = conn.execute(
                "SELECT id, title, price_cents, stock FROM products WHERE id = ANY(%s) "
                "ORDER BY id FOR UPDATE", (sorted(wanted),)).fetchall()
            found = {r["id"]: r for r in rows}
            for pid in wanted:
                if pid not in found:
                    raise HTTPException(404, f"produto {pid} não existe")
            for pid, qty in wanted.items():
                if found[pid]["stock"] < qty:
                    raise HTTPException(409, f"estoque insuficiente para '{found[pid]['title']}' "
                                             f"(disponível: {found[pid]['stock']})")
            total = sum(found[pid]["price_cents"] * qty for pid, qty in wanted.items())
            conn.execute("INSERT INTO orders (id, idempotency_key, customer_name, total_cents) "
                         "VALUES (%s, %s, %s, %s)", (order_id, idempotency_key, body.customer_name, total))
            for pid, qty in wanted.items():
                conn.execute("UPDATE products SET stock = stock - %s WHERE id = %s", (qty, pid))
                conn.execute("INSERT INTO order_items VALUES (%s, %s, %s, %s)",
                             (order_id, pid, qty, found[pid]["price_cents"]))
            conn.execute("INSERT INTO outbox (order_id, payload) VALUES (%s, %s::jsonb)",
                         (order_id, json.dumps({"order_id": order_id, "total_cents": total,
                                                "conversation_id": x_conversation_id})))
            order = load_order(conn, order_id)
    except psycopg.errors.UniqueViolation:  # duas requisições simultâneas com a mesma chave
        existing = replay(idempotency_key)
        if existing:
            return JSONResponse(status_code=200, content={**existing, "idempotent_replay": True})
        raise
    emf("OrdersCreated", 1)
    log(logging.INFO, "pedido criado", order_id=order_id, total_cents=total,
        conversation_id=x_conversation_id)
    return JSONResponse(status_code=201, content=order)


@app.get("/orders/{order_id}")
def get_order(order_id: str):
    with pool.connection(timeout=5) as conn:
        o = load_order(conn, order_id)
    if not o:
        raise HTTPException(404, "pedido não encontrado")
    return o


@app.get("/orders")
def list_orders(limit: int = 20):
    limit = max(1, min(limit, 100))
    with pool.connection(timeout=5) as conn:
        rows = conn.execute("SELECT id FROM orders ORDER BY created_at DESC LIMIT %s", (limit,)).fetchall()
        return [load_order(conn, r["id"]) for r in rows]
