"""
Locust load test against a vLLM OpenAI-compatible server. HttpUser's default request
timing measures time-to-LAST-byte, which hides the metric that actually matters for an
interactive LLM (time-to-FIRST-token) — so this fires the request manually with
streaming and reports TTFT as a custom Locust metric ("ttft_ms") alongside the normal
one (full request latency, "total_ms").

Usage: locust -f locustfile.py --host http://<node0 ip>:8000
       (or headless: locust -f locustfile.py --host ... --headless -u 10 -r 2 -t 60s)
"""
import json
import time

from locust import HttpUser, task, between, events

PROMPTS = [
    "Explain the CAP theorem in two sentences.",
    "Write a haiku about GPUs.",
    "What is the difference between NVLink and InfiniBand?",
    "Summarize why time-to-first-token matters for chat UIs.",
]

MODEL_NAME = None  # resolved lazily from /v1/models on first request


class VLLMUser(HttpUser):
    wait_time = between(0.5, 2.0)

    @task
    def completion(self):
        global MODEL_NAME
        if MODEL_NAME is None:
            resp = self.client.get("/v1/models", name="/v1/models")
            MODEL_NAME = resp.json()["data"][0]["id"]

        prompt = PROMPTS[int(time.time() * 1000) % len(PROMPTS)]
        start = time.perf_counter()
        ttft = None
        n_tokens = 0
        exc = None

        try:
            with self.client.post(
                "/v1/completions",
                json={"model": MODEL_NAME, "prompt": prompt, "max_tokens": 128, "stream": True},
                stream=True,
                name="/v1/completions (streamed)",
                catch_response=True,
            ) as resp:
                for line in resp.iter_lines():
                    if not line or not line.startswith(b"data:"):
                        continue
                    payload = line[len(b"data:"):].strip()
                    if payload == b"[DONE]":
                        break
                    if ttft is None:
                        ttft = time.perf_counter() - start
                    chunk = json.loads(payload)
                    if chunk["choices"][0].get("text"):
                        n_tokens += 1
                resp.success()
        except Exception as e:
            exc = e

        total = time.perf_counter() - start

        # Note: resp.success() above also fires Locust's own default stat entry for
        # "/v1/completions (streamed)" with its own (less meaningful, mid-stream) timing.
        # Watch "ttft_ms" and "/v1/completions (total)" below as the real numbers.
        #
        # Report the streamed request's real latency (Locust's own HttpUser timing for
        # a stream=True request only captures headers, not the full body) plus a
        # dedicated custom metric for TTFT so it shows up in Locust's stats table.
        events.request.fire(
            request_type="POST",
            name="/v1/completions (total)",
            response_time=total * 1000,
            response_length=n_tokens,
            exception=exc,
        )
        if ttft is not None:
            events.request.fire(
                request_type="TTFT",
                name="ttft_ms",
                response_time=ttft * 1000,
                response_length=0,
                exception=None,
            )
