#!/usr/bin/env bash
set -euo pipefail

trap 'echo "Stopping..."; exit 0' INT TERM

echo "[startup] Kuzco worker bootstrap (legal/clean mode)"

# =========[ Konfigurasi dasar ]=========
: "${CODE:?Missing CODE env (worker code)}"
: "${OLLAMA_HOST:=http://localhost:14444}"     # proxy Hyperbolic lokal
: "${WORKER_NAME:=GOLDVPS-DEVNET-01}"          # bebas, tapi stabil
: "${WORKER_CAPACITY:=1}"
: "${MAX_CONCURRENCY:=1}"

export OLLAMA_HOST
export WORKER_NAME
export WORKER_CAPACITY
export MAX_CONCURRENCY

# Tetap prefer IPv4 bila Node.js dipakai oleh CLI
export NODE_OPTIONS="${NODE_OPTIONS:---dns-result-order=ipv4first}"

echo "[check] OLLAMA_HOST  = $OLLAMA_HOST"
echo "[check] WORKER_NAME  = $WORKER_NAME"
echo "[check] CAPACITY     = $WORKER_CAPACITY"
echo "[check] CONCURRENCY  = $MAX_CONCURRENCY"

# =========[ Readiness check proxy Hyperbolic ]=========
echo "[wait] Waiting Hyperbolic proxy at $OLLAMA_HOST ..."
until curl -4fsS "$OLLAMA_HOST/health" >/dev/null 2>&1 \
  && curl -4fsS "$OLLAMA_HOST/api/tags" >/dev/null 2>&1 \
  && curl -4fsS "$OLLAMA_HOST/v1/models" >/dev/null 2>&1 ; do
  sleep 1
done
echo "[ok] Proxy ready!"

# (Opsional) uji singkat completion lokal (tidak wajib)
if command -v jq >/dev/null 2>&1; then
  echo "[test] Sanity check /v1/chat/completions"
  curl -4sS -X POST "$OLLAMA_HOST/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"test","messages":[{"role":"user","content":"say ok"}],"max_tokens":8}' \
    | jq -r '.choices[0].message.content' || true
fi

# =========[ Start worker ]=========
echo "[run] Starting Kuzco inference node..."
# Flag/ENV untuk capacity/concurrency biasanya dibaca oleh launcher;
# tetap diexport supaya control-plane bisa melihatnya via env.
exec inference node start --code "$CODE"
