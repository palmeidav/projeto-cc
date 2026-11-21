#!/bin/bash
# 1) gera o .docx num container (node + docx)  2) converte para PDF pelo Microsoft Word
set -euo pipefail
cd "$(dirname "$0")/../.."
docker run --rm -v "$PWD":/work -w /work/relatorio/word node:20.18.1-bookworm-slim bash -c '
  [ -d node_modules/docx ] || npm install --silent --no-audit --no-fund docx@9.5.0 >/dev/null
  node gerar-docx.js'
