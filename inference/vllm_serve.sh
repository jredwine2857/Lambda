#!/usr/bin/env bash
# Starts vLLM's OpenAI-compatible server. Exposes /metrics for Prometheus automatically.
# Usage: MODEL_NAME=Qwen/Qwen2.5-1.5B-Instruct bash vllm_serve.sh [--background]
set -euo pipefail

VENV_BIN="$HOME/venv/bin"
source "$VENV_BIN/activate" 2>/dev/null || true

MODEL_NAME="${MODEL_NAME:-Qwen/Qwen2.5-1.5B-Instruct}"
PORT="${PORT:-8000}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.85}"

wait_for_health() {
  echo "Waiting for vLLM to answer on :${PORT} (model weights download on first run)..."
  for _ in $(seq 1 90); do
    if curl -sf "http://localhost:${PORT}/health" >/dev/null 2>&1; then
      echo "vLLM is up."
      return 0
    fi
    sleep 5
  done
  return 1
}

if [[ "${1:-}" == "--background" ]]; then
  # A plain backgrounded process (even with setsid) is not safe here: GitHub Actions'
  # runner kills leftover processes when a job finishes ("Cleaning up orphan
  # processes"), so the server would die between the deploy job and the load-test job
  # that needs it. A transient systemd unit is owned by systemd, not the runner.
  if command -v systemd-run &>/dev/null && sudo -n true 2>/dev/null; then
    sudo systemctl stop vllm-lab 2>/dev/null || true
    sudo systemctl reset-failed vllm-lab 2>/dev/null || true
    sudo systemd-run --unit=vllm-lab --collect \
      --setenv=HOME="$HOME" \
      --setenv=HF_HOME="$HOME/.cache/huggingface" \
      "$VENV_BIN/vllm" serve "$MODEL_NAME" \
        --host 0.0.0.0 --port "$PORT" --gpu-memory-utilization "$GPU_MEM_UTIL"
    echo "vLLM started as systemd unit vllm-lab (journalctl -u vllm-lab -f for logs)."
  else
    setsid nohup "$VENV_BIN/vllm" serve "$MODEL_NAME" \
      --host 0.0.0.0 --port "$PORT" --gpu-memory-utilization "$GPU_MEM_UTIL" \
      > vllm.log 2>&1 < /dev/null &
    echo "vLLM starting in background (pid $!), logs in vllm.log"
  fi

  if wait_for_health; then
    exit 0
  fi
  echo "vLLM did not become healthy in time. Recent logs:" >&2
  sudo journalctl -u vllm-lab --no-pager -n 50 2>/dev/null || tail -n 50 vllm.log 2>/dev/null || true
  exit 1
else
  exec vllm serve "$MODEL_NAME" --host 0.0.0.0 --port "$PORT" \
    --gpu-memory-utilization "$GPU_MEM_UTIL"
fi
