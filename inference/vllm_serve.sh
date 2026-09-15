#!/usr/bin/env bash
# Starts vLLM's OpenAI-compatible server. Exposes /metrics for Prometheus automatically.
# Usage: MODEL_NAME=Qwen/Qwen2.5-1.5B-Instruct bash vllm_serve.sh [--background]
set -euo pipefail
source ~/venv/bin/activate 2>/dev/null || true

MODEL_NAME="${MODEL_NAME:-Qwen/Qwen2.5-1.5B-Instruct}"
PORT="${PORT:-8000}"

CMD=(vllm serve "$MODEL_NAME" --host 0.0.0.0 --port "$PORT" --gpu-memory-utilization 0.85)

if [[ "${1:-}" == "--background" ]]; then
  # setsid detaches from this shell's process group so the server survives past a
  # CI job step or SSH session ending (plain `&` alone isn't reliably enough for that).
  setsid nohup "${CMD[@]}" > vllm.log 2>&1 < /dev/null &
  echo "vLLM starting in background (pid $!), logs in vllm.log"
  echo "Waiting for it to come up on :$PORT..."
  for i in $(seq 1 60); do
    if curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1; then
      echo "vLLM is up."
      exit 0
    fi
    sleep 5
  done
  echo "vLLM did not become healthy in time — check vllm.log" >&2
  exit 1
else
  exec "${CMD[@]}"
fi
