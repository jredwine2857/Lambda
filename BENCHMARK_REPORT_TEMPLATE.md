# PoC Benchmark Report — 2-Node Lambda GPU Cluster

*Fill this in after running the lab. Written the way you'd hand it to a customer's
technical lead — lead with the answer, back it with numbers, and be explicit about
what you did and didn't test.*

## Environment

- Instance type: `___` (e.g. gpu_1x_a10), 2 nodes, region `___`
- GPU: `___`, driver `___`, CUDA `___`
- Interconnect: `___` (public internet / private VPC — note this; it changes every
  number below and is the single biggest caveat in a real PoC)
- Model under test: `___`
- Date / duration cluster was up: `___`

## 1. Network health (NCCL)

- Achieved all-reduce bandwidth: `___` GB/s
- Interpretation: is this in the range you'd expect for the interconnect above? What
  would you tell a customer if this number came back low?

## 2. Distributed training (PyTorch DDP)

- Avg step time (steady state): `___` ms, global batch size `___`
- Implied samples/sec: `___`
- What fraction of step time is compute vs. the gradient all-reduce? (You can estimate
  this by comparing single-node step time to 2-node step time.)

## 3. Inference serving (vLLM)

- TTFT p50 / p95 (single request, `ttft_client.py`): `___` / `___` ms
- TTFT p50 / p99 under load (`benchmark_serving.py`, N concurrent): `___` / `___` ms
- Throughput at that concurrency: `___` req/s, `___` output tok/s
- GPU utilization during load (from Grafana): `___`%
- At what concurrency did TTFT start to degrade noticeably? `___`

## 4. Cost framing

- Instance cost: `___`/hr per node x 2 nodes
- Cost per 1M output tokens at measured throughput: `___`
- One sentence a customer's finance stakeholder would actually read: `___`

## 5. What I'd test next with more time/nodes

- e.g. multi-GPU-per-node NVLink scaling, InfiniBand vs Ethernet comparison,
  TensorRT-LLM vs vLLM, larger model / tensor parallelism, SLURM vs Kubernetes
  orchestration overhead.
