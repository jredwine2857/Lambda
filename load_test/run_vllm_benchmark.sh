#!/usr/bin/env bash
# Runs vLLM's own benchmark_serving.py, which reports TTFT/ITL/throughput percentiles
# directly — the number you'd actually put in a customer-facing benchmark report.
# Usage: bash run_vllm_benchmark.sh <node0_ip> [model_name] [num_prompts]
set -euo pipefail

NODE0_IP="${1:?Usage: $0 <node0_ip> [model_name] [num_prompts]}"
MODEL_NAME="${2:-Qwen/Qwen2.5-1.5B-Instruct}"
NUM_PROMPTS="${3:-100}"

WORKDIR="$(mktemp -d)"
git clone --depth 1 https://github.com/vllm-project/vllm.git "$WORKDIR/vllm"

python3 -m venv "$WORKDIR/venv"
source "$WORKDIR/venv/bin/activate"
pip install --quiet vllm requests transformers datasets pandas

python3 "$WORKDIR/vllm/benchmarks/benchmark_serving.py" \
  --backend vllm \
  --base-url "http://${NODE0_IP}:8000" \
  --model "$MODEL_NAME" \
  --dataset-name random \
  --random-input-len 128 \
  --random-output-len 128 \
  --num-prompts "$NUM_PROMPTS" \
  --save-result --result-filename "benchmark_result_$(date +%s).json"

echo ""
echo "Look for mean/p50/p99 TTFT, inter-token latency, and request throughput in the"
echo "output above and in the saved JSON — that's the headline slide for a PoC report."
