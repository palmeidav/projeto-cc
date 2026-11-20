"""chat-service: vendedor de IA (Amazon Bedrock, Converse API com tools) que consulta o catálogo
e registra pedidos chamando o catalog-orders-service."""
import json
import logging
import os
import re
import time
import uuid
from contextlib import asynccontextmanager
from typing import Optional

import boto3
import httpx
from botocore.config import Config
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field

from logsetup import emf, log, setup

setup()

REGION = os.getenv("AWS_REGION", "us-east-2")
CATALOG_URL = os.environ["CATALOG_URL"].rstrip("/")
MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "")
LLM_MODE = os.getenv("LLM_MODE", "bedrock")  # "bedrock" (real) ou "mock" (sem IA: testes de carga/local)
MAX_TOOL_ROUNDS = 6
MAX_HISTORY = 40

pool = ConnectionPool(
    make_conninfo(host=os.environ["DB_HOST"], port=os.getenv("DB_PORT", "5432"),
                  dbname=os.getenv("DB_NAME", "shop"), user=os.environ["DB_USER"],
                  password=os.environ["DB_PASSWORD"], connect_timeout="5",
                  sslmode=os.getenv("DB_SSLMODE", "prefer")),
    min_size=1, max_size=int(os.getenv("DB_POOL_MAX", "10")), kwargs={"row_factory": dict_row},
    check=ConnectionPool.check_connection, open=False)

bedrock = boto3.client(
    "bedrock-runtime", region_name=REGION,
    config=Config(read_timeout=30, connect_timeout=5, retries={"max_attempts": 3, "mode": "adaptive"}))
http = httpx.Client(timeout=httpx.Timeout(5.0, connect=2.0))

SYSTEM_PROMPT = (
    "Você é a Marina, vendedora virtual da Livraria Nuvem. Atenda em português do Brasil, de forma "
    "cordial e objetiva. Use SEMPRE as ferramentas para consultar o catálogo e o estoque: nunca invente "
    "títulos, preços ou disponibilidade. Para fechar uma compra, confirme com o cliente o nome, os livros "
    "e as quantidades; só então chame create_order. Só diga que um pedido foi registrado se a ferramenta "
    "retornar ok=true, e informe o código do pedido (order_id). Se a ferramenta falhar, avise o cliente "
    "com clareza e não afirme que o pedido foi feito. Você pode oferecer desconto de até 5% apenas se o "
    "cliente comprar 3 ou mais livros (informe o valor, mas o preço final é o do sistema)."
)

TOOLS = {"tools": [
    {"toolSpec": {
        "name": "search_products",
        "description": "Busca livros no catálogo por título, autor ou categoria. Use query vazia para listar.",
        "inputSchema": {"json": {"type": "object", "properties": {"query": {"type": "string"}},
                                 "required": ["query"]}}}},
    {"toolSpec": {
        "name": "check_stock",
        "description": "Consulta preço e estoque atual de um livro pelo product_id.",
        "inputSchema": {"json": {"type": "object", "properties": {"product_id": {"type": "integer"}},
                                 "required": ["product_id"]}}}},
    {"toolSpec": {
        "name": "create_order",
        "description": "Registra um pedido de compra. Chame somente depois do cliente confirmar nome, "
                       "livros e quantidades.",
        "inputSchema": {"json": {"type": "object", "properties": {
            "customer_name": {"type": "string"},
            "items": {"type": "array", "items": {"type": "object", "properties": {
                "product_id": {"type": "integer"}, "quantity": {"type": "integer"}},
                "required": ["product_id", "quantity"]}}},
            "required": ["customer_name", "items"]}}}},
]}


# ------------------------------------------------------------------ persistência das conversas
def init_db():
    for attempt in range(1, 31):
        try:
            with pool.connection(timeout=10) as conn:
                conn.execute("SELECT pg_advisory_xact_lock(43)")
                conn.execute("CREATE TABLE IF NOT EXISTS conversations ("
                             "id TEXT PRIMARY KEY, messages JSONB NOT NULL DEFAULT '[]', "
                             "updated_at TIMESTAMPTZ NOT NULL DEFAULT now())")
            return
        except Exception as e:
            log(logging.WARNING, "aguardando o banco", tentativa=attempt, erro=str(e)[:200])
            time.sleep(2)
    raise RuntimeError("banco indisponível na inicialização")


@asynccontextmanager
async def lifespan(app):
    pool.open(wait=False)
    init_db()
    yield
    pool.close()


app = FastAPI(title="chat-service", lifespan=lifespan)


def load_messages(conv_id):
    with pool.connection(timeout=5) as conn:
        row = conn.execute("SELECT messages FROM conversations WHERE id = %s", (conv_id,)).fetchone()
    return row["messages"] if row else []


def save_messages(conv_id, messages):
    with pool.connection(timeout=5) as conn:
        conn.execute(
            "INSERT INTO conversations (id, messages) VALUES (%s, %s) "
            "ON CONFLICT (id) DO UPDATE SET messages = EXCLUDED.messages, updated_at = now()",
            (conv_id, Jsonb(messages)))


def trim(messages):
    """Limita o histórico sem quebrar pares toolUse/toolResult: começa sempre em uma fala do cliente."""
    messages = messages[-MAX_HISTORY:]
    while messages and not (messages[0]["role"] == "user"
                            and not any("toolResult" in b for b in messages[0]["content"])):
        messages.pop(0)
    return messages


# ------------------------------------------------------------------ ferramentas (chamam o catálogo)
def call_catalog(method, path, conv_id, **kw):
    """Chamada ao catálogo com até 3 tentativas (seguro também para POST: há Idempotency-Key)."""
    headers = {"X-Correlation-ID": conv_id, **kw.pop("headers", {})}
    last = None
    for attempt in range(3):
        try:
            r = http.request(method, f"{CATALOG_URL}{path}", headers=headers, **kw)
            if r.status_code < 500:
                return r
            last = RuntimeError(f"catálogo respondeu {r.status_code}")
        except httpx.HTTPError as e:
            last = e
        time.sleep(0.3 * (attempt + 1))
    raise last


def run_tool(name, args, conv_id, tool_use_id):
    try:
        if name == "search_products":
            r = call_catalog("GET", "/products", conv_id, params={"q": args.get("query", "")})
        elif name == "check_stock":
            r = call_catalog("GET", f"/products/{int(args['product_id'])}", conv_id)
        elif name == "create_order":
            payload = {"customer_name": args["customer_name"],
                       "items": [{"product_id": int(i["product_id"]), "quantity": int(i["quantity"])}
                                 for i in args["items"]]}
            # a chave é única por chamada de ferramenta: repetir a mesma chamada nunca duplica o pedido
            r = call_catalog("POST", "/orders", conv_id, json=payload,
                             headers={"Idempotency-Key": f"{conv_id}:{tool_use_id}"})
        else:
            return {"ok": False, "error": f"ferramenta desconhecida: {name}"}
        data = r.json()
        return {"ok": r.is_success, "status": r.status_code, "data": data}
    except Exception as e:
        log(logging.ERROR, "falha ao executar ferramenta", tool=name, conversation_id=conv_id, erro=repr(e)[:300])
        return {"ok": False, "error": "serviço de catálogo indisponível no momento"}


# ------------------------------------------------------------------ LLM
def mock_llm(messages):
    """Substituto sem IA (LLM_MODE=mock). Aceita 'pedido: Nome; 1x2,3x1' para testar a criação de pedidos."""
    last = messages[-1]
    results = [b["toolResult"] for b in last["content"] if "toolResult" in b]
    if results:
        text = results[0]["content"][0]["text"]
        try:
            res = json.loads(text)
        except ValueError:
            res = {}
        data = res.get("data")
        if isinstance(data, list):
            titles = ", ".join(p["title"] for p in data[:3]) or "nenhum livro"
            reply = f"[modo demonstração] Encontrei: {titles}."
        elif isinstance(data, dict) and "order_id" in data:
            reply = f"[modo demonstração] Pedido registrado! Código: {data['order_id']}."
        else:
            reply = f"[modo demonstração] Não consegui concluir: {res.get('error') or data}"
        return {"stopReason": "end_turn", "output": {"message": {"role": "assistant", "content": [{"text": reply}]}}}
    user_text = " ".join(b.get("text", "") for b in last["content"])
    m = re.match(r"\s*pedido:\s*([^;]+);\s*(.+)", user_text, re.I)
    if m:
        items = [{"product_id": int(a), "quantity": int(b)} for a, b in re.findall(r"(\d+)x(\d+)", m.group(2))]
        tool = {"name": "create_order", "input": {"customer_name": m.group(1).strip(), "items": items}}
    else:
        tool = {"name": "search_products", "input": {"query": ""}}
    return {"stopReason": "tool_use", "output": {"message": {"role": "assistant", "content": [
        {"toolUse": {"toolUseId": uuid.uuid4().hex[:16], **tool}}]}}}


def llm(messages):
    if LLM_MODE == "mock":
        return mock_llm(messages)
    start = time.time()
    resp = bedrock.converse(modelId=MODEL_ID, system=[{"text": SYSTEM_PROMPT}], messages=messages,
                            toolConfig=TOOLS, inferenceConfig={"maxTokens": 800, "temperature": 0.3})
    emf("LLMLatencyMs", int((time.time() - start) * 1000), "Milliseconds")
    return resp


# ------------------------------------------------------------------ conversa
def chat_turn(conv_id, user_text):
    """Executa um turno. O estado é salvo após cada rodada de ferramentas: se o LLM falhar depois de um
    pedido já registrado, o histórico mantém o resultado e o próximo turno não duplica o pedido."""
    messages = trim(load_messages(conv_id))
    if messages and messages[-1]["role"] == "user":      # turno anterior terminou logo após as ferramentas
        messages[-1]["content"].append({"text": user_text})
    else:
        messages.append({"role": "user", "content": [{"text": user_text}]})
    orders = []
    for _ in range(MAX_TOOL_ROUNDS):
        resp = llm(messages)
        msg = resp["output"]["message"]
        messages.append(msg)
        if resp["stopReason"] != "tool_use":
            save_messages(conv_id, messages)
            return "".join(b.get("text", "") for b in msg["content"]).strip(), False, orders
        results = []
        for block in msg["content"]:
            if "toolUse" in block:
                tu = block["toolUse"]
                res = run_tool(tu["name"], tu["input"], conv_id, tu["toolUseId"])
                if tu["name"] == "create_order" and res.get("ok"):
                    orders.append(res["data"]["order_id"])
                results.append({"toolResult": {"toolUseId": tu["toolUseId"],
                                               "content": [{"text": json.dumps(res, ensure_ascii=False)}]}})
        messages.append({"role": "user", "content": results})
        save_messages(conv_id, messages)
    return "Não consegui concluir esse pedido agora. Pode repetir, por favor?", True, orders


class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    conversation_id: Optional[str] = Field(default=None, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")


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


@app.get("/health")
def health():
    """Liveness: não depende de banco, catálogo nem Bedrock."""
    return {"status": "ok"}


@app.get("/ready")
def ready():
    try:
        with pool.connection(timeout=3) as conn:
            conn.execute("SELECT 1")
        return {"status": "ready", "llm_mode": LLM_MODE}
    except Exception:
        return JSONResponse(status_code=503, content={"status": "db indisponível"})


@app.post("/chat")
def chat(body: ChatIn):
    conv_id = body.conversation_id or uuid.uuid4().hex
    try:
        reply, degraded, orders = chat_turn(conv_id, body.message)
    except Exception as e:
        # LLM/banco indisponível: resposta amigável (HTTP 200) e erro registrado para o alarme de falhas
        log(logging.ERROR, "falha no turno de conversa", conversation_id=conv_id, erro=repr(e)[:400])
        emf("ChatDegraded", 1)
        try:  # pedido já registrado neste turno? (o histórico salvo contém o resultado)
            hist = load_messages(conv_id)
            last_ok = [json.loads(b["toolResult"]["content"][0]["text"]) for m in hist[-4:] if m["role"] == "user"
                       for b in m["content"] if "toolResult" in b]
            orders = [r["data"]["order_id"] for r in last_ok if r.get("ok") and isinstance(r.get("data"), dict)
                      and "order_id" in r["data"]]
        except Exception:
            orders = []
        reply = "Tive um problema técnico para responder agora. Por favor, tente novamente em instantes."
        if orders:
            reply += f" Seu pedido {orders[-1]} já foi registrado."
        return {"conversation_id": conv_id, "reply": reply, "degraded": True}
    if degraded:
        emf("ChatDegraded", 1)
    return {"conversation_id": conv_id, "reply": reply, "degraded": degraded}


@app.get("/conversations/{conv_id}")
def get_conversation(conv_id: str):
    msgs = load_messages(conv_id)
    if not msgs:
        raise HTTPException(404, "conversa não encontrada")
    return [{"role": m["role"], "text": " ".join(b["text"] for b in m["content"] if "text" in b)}
            for m in msgs if any("text" in b for b in m["content"])]
