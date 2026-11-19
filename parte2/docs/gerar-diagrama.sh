#!/bin/bash
# Gera docs/diagrama-arquitetura.png num container (graphviz + diagrams), sem instalar nada no Mac,
# e ajusta para 16:9 exato (3840x2160) com margem branca.
set -euo pipefail
cd "$(dirname "$0")/.."
docker run --rm -v "$PWD":/work -w /work python:3.12.8-slim bash -c '
  apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends graphviz fonts-dejavu-core >/dev/null 2>&1 &&
  pip install -q --root-user-action=ignore --disable-pip-version-check "diagrams==0.24.4" &&
  python docs/diagrama_arquitetura.py'
f=docs/diagrama-arquitetura.png
w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}'); h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
if [ $((w*9)) -gt $((h*16)) ]; then nh=$((w*9/16)); nw=$w; else nw=$((h*16/9)); nh=$h; fi
sips --padToHeightWidth $nh $nw --padColor FFFFFF "$f" >/dev/null
sips --resampleHeightWidth 2160 3840 "$f" >/dev/null
echo "gerado: $f ($(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')x$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}'))"
