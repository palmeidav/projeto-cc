#!/bin/bash
# Testes rápidos do ambiente local (docker compose up --build já rodando).
H='Content-Type: application/json'
echo "== saúde"; curl -s localhost:8000/ready; echo; curl -s localhost:8001/ready; echo
echo "== catálogo (busca por autor)"; curl -s "localhost:8001/products?q=machado"; echo
echo "== conversa com o vendedor"
curl -s -X POST localhost:8000/chat -H "$H" -d '{"message":"Quais livros vocês têm?","conversation_id":"demo1"}'; echo
echo "== pedido pela conversa (modo mock: 'pedido: Nome; id x qtd')"
curl -s -X POST localhost:8000/chat -H "$H" -d '{"message":"pedido: Maria; 1x2,9x1","conversation_id":"demo1"}'; echo
sleep 3
echo "== pedidos (o worker muda PENDING para CONFIRMED)"; curl -s "localhost:8001/orders?limit=3"; echo
echo "== idempotência: mesma chave duas vezes gera 1 pedido"
for i in 1 2; do curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST localhost:8001/orders -H "$H" -H 'Idempotency-Key: demo-key' -d '{"customer_name":"Teste","items":[{"product_id":1,"quantity":1}]}'; done
