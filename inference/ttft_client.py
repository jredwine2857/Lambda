"""
Measures time-to-first-token against a running vLLM OpenAI-compatible server by
streaming a completion and timing the first SSE chunk.

Usage: python3 ttft_client.py --url http://<node0 ip>:8000 --prompt "..." [--n 5]
"""
import argparse
import json
import time

import requests


def one_request(base_url: str, model: str, prompt: str, max_tokens: int):
    t0 = time.perf_counter()
    resp = requests.post(
        f"{base_url}/v1/completions",
        json={"model": model, "prompt": prompt, "max_tokens": max_tokens, "stream": True},
        stream=True,
        timeout=60,
    )
    resp.raise_for_status()

    ttft = None
    n_tokens = 0
    for line in resp.iter_lines():
        if not line or not line.startswith(b"data:"):
            continue
        payload = line[len(b"data:"):].strip()
        if payload == b"[DONE]":
            break
        if ttft is None:
            ttft = time.perf_counter() - t0
        chunk = json.loads(payload)
        text = chunk["choices"][0].get("text", "")
        n_tokens += 1 if text else 0

    total = time.perf_counter() - t0
    return ttft, total, n_tokens


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True, help="e.g. http://1.2.3.4:8000")
    ap.add_argument("--model", default=None, help="defaults to whatever /v1/models reports")
    ap.add_argument("--prompt", default="Explain NCCL in two sentences.")
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--n", type=int, default=5, help="number of requests to average over")
    args = ap.parse_args()

    model = args.model
    if model is None:
        models = requests.get(f"{args.url}/v1/models", timeout=10).json()
        model = models["data"][0]["id"]

    ttfts, totals = [], []
    for i in range(args.n):
        ttft, total, n_tokens = one_request(args.url, model, args.prompt, args.max_tokens)
        ttfts.append(ttft)
        totals.append(total)
        tok_s = n_tokens / total if total else 0
        print(f"req {i}: ttft={ttft*1000:.1f}ms total={total*1000:.1f}ms "
              f"tokens={n_tokens} decode_tok/s={tok_s:.1f}")

    ttfts.sort()
    p50 = ttfts[len(ttfts) // 2]
    print(f"\nmodel={model} n={args.n} ttft_p50={p50*1000:.1f}ms "
          f"ttft_avg={sum(ttfts)/len(ttfts)*1000:.1f}ms")


if __name__ == "__main__":
    main()
