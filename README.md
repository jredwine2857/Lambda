# Lambda GPU Lab — 2-Node Cluster PoC Kit

A self-contained lab for learning Lambda Cloud hands-on before an interview: provision a
2-node GPU cluster, verify the network with an NCCL bandwidth test, run a small
multi-node PyTorch DDP job, deploy a light LLM with vLLM, watch it all in
Prometheus/Grafana, and load-test it with Locust / vLLM's `benchmark_serving`.

## Why this shape (tie-in to the Senior Solution Engineer JD)

The role is technical pre-sales: designing PoCs, running benchmark evaluations on
training *and* inference workloads, and presenting results to CTOs/Heads of AI. This lab
is a miniature version of exactly that workflow:

| Lab step | Maps to JD bullet |
|---|---|
| `infra/` provision 2 nodes | "design end-to-end GPU cloud solutions", Terraform/Ansible |
| `distributed/nccl_bandwidth_test.py` | validating cluster networking / interconnect health before a PoC |
| `distributed/ddp_train.py` | "distributed training" benchmarking (PyTorch) |
| `inference/vllm_serve.sh` + TTFT client | "inference optimization (vLLM, TensorRT-LLM)" |
| `monitoring/` Prometheus+Grafana | "observability" guidance you'd give a customer |
| `load_test/` Locust + `benchmark_serving` | "benchmark evaluations... show tangible performance and cost advantages" |
| `BENCHMARK_REPORT_TEMPLATE.md` | "author comprehensive proposals" — a customer-facing PoC summary |

**Concepts named in the JD that this lab does NOT cover hands-on** (budget is 2 nodes /
2 days) but you should be able to talk about: SLURM vs Kubernetes for multi-node
orchestration, InfiniBand/RoCE vs plain Ethernet (why it matters for NCCL allreduce at
scale), distributed filesystems (NFS, NVMe-oF, Weka, VAST), TensorRT-LLM as vLLM's
alternative, and 3D parallelism / Megatron-LM for large-model training. Knowing the
*shape* of each answer matters more than depth for a first interview.

## Architecture

```
                 ┌─────────────────────────────┐
                 │           node0              │
                 │  (control + monitoring)      │
                 │                               │
                 │  Prometheus :9090 ───────────┼──scrapes──┐
                 │  Grafana    :3000             │           │
                 │  dcgm-exporter :9400 ─────────┤           │
                 │  node-exporter :9100 ─────────┤           │
                 │  vLLM server  :8000 ──────────┤ (metrics) │
                 │  GPU 0                        │           │
                 └──────────────┬────────────────┘           │
                                 │  NCCL / torchrun rendezvous │
                                 │  (private or public IP)     │
                 ┌──────────────┴────────────────┐           │
                 │           node1                │           │
                 │  dcgm-exporter :9400 ◄──────────────────────┘
                 │  node-exporter :9100 ◄──────────────────────┘
                 │  GPU 0                          │
                 └─────────────────────────────────┘
```

Both nodes run the GPU/metrics exporters; only node0 runs Prometheus+Grafana and scrapes
node1 remotely. vLLM and the training job can run on either node — scripts assume node0
for simplicity.

## Prerequisites

- A Lambda Cloud account with billing enabled and an API key
  (Cloud dashboard → API keys). **Running 2 GPU nodes costs real money per hour — always
  run `infra/terminate_cluster.sh` when you're done for the day.** As of 2026-09-15,
  `1x A10 (24GB PCIe)` at $1.29/hr was the cheapest single-GPU SKU in the Lambda Cloud
  launch dialog — two of those is ~$2.58/hr for the whole cluster, so budget a few
  dollars for a couple hours of hands-on time. Confirm current pricing before you
  launch; it moves.
- An SSH key uploaded to Lambda Cloud, private half on your machine.
- Local tools: `curl`, `jq`, `ssh`. (Windows: use WSL or Git Bash — these scripts are
  bash, meant to run from your machine to drive the API, then on the nodes themselves
  over SSH.)

Copy `.env.example` to `.env` and fill in `LAMBDA_API_KEY`, `SSH_KEY_NAME`, and
`INSTANCE_TYPE` (default assumes a cheap single-GPU type like `gpu_1x_a10`; run
`infra/lambda_cloud_api.sh list-types` to see what's available/in-stock in your region).

## Automated path: GitHub Actions CI/CD (recommended)

`.github/workflows/gpu-lab.yml` runs the entire lab end-to-end on demand: Terraform
provisions the 2 nodes, each node is registered as a **persistent** self-hosted GitHub
Actions runner (persistent, not `--ephemeral`, because each node needs to pick up
several jobs in sequence — nccl, then ddp, then vLLM), NCCL and DDP run as genuinely
parallel multi-node jobs across the two runners, vLLM gets deployed, Locust load-tests
it from a hosted runner, and — critically — a `teardown` job with `if: always()` runs
`terraform destroy` no matter what else failed, so a broken run can't leave GPUs
billing overnight.

```
                 ┌── nccl-node0 ──┐        ┌── ddp-node0 ──┐
  provision ─────┤                ├────────┤               ├── deploy-vllm ── load-test ── teardown
                 └── nccl-node1 ──┘        └── ddp-node1 ──┘                  (always runs)
```

**Security note:** the workflow is `workflow_dispatch`-only, deliberately. Self-hosted
runners triggered by `pull_request` (even from your own public repo's forks) is a
known way to let arbitrary PR code execute on your infrastructure — never wire this
trigger to anything but a manual, write-access-gated event.

### One-time setup

```bash
git init
gh repo create lambda-gpu-lab --private --source=. --push   # or push to an existing repo
```

Add these as repo secrets (Settings → Secrets and variables → Actions, or `gh secret set NAME`):

| Secret | Value |
|---|---|
| `LAMBDA_API_KEY` | Lambda Cloud dashboard → API keys |
| `SSH_KEY_NAME` | The SSH key's name as it appears in Lambda Cloud |
| `SSH_PRIVATE_KEY` | The matching private key (PEM), so the `provision` job can SSH in and install the runner |
| `GH_PAT` | A classic PAT with `repo` scope (or fine-grained: Administration: Read & write on this repo) — used to mint runner registration tokens and to deregister runners at teardown. The default `GITHUB_TOKEN` cannot manage self-hosted runners. |

### Run it

Actions tab → **GPU Lab Pipeline** → **Run workflow** → `mode: full`. If a run ever
gets stuck mid-pipeline, re-run with `mode: destroy_only` to force a `terraform
destroy` without needing to SSH in manually.

### Terraform vs OpenTofu

The workflow uses Terraform (`hashicorp/setup-terraform`) because the JD for this role
names Terraform explicitly. OpenTofu is a near-identical drop-in if you'd rather avoid
HashiCorp's BSL license: swap `hashicorp/setup-terraform@v3` for
`opentofu/setup-opentofu@v1`, and `terraform` for `tofu` in every `run:` step — the HCL
in `infra/terraform/*.tf` doesn't change at all.

## Manual path (debugging, or if you'd rather not wire up GitHub Actions)

The same scripts the workflow calls can be run by hand, which is also the fastest way
to debug a step that's failing in CI.

### Step-by-step

### 1. Provision the cluster

```bash
cd infra
source ../.env
./launch_cluster.sh
```

This launches 2 identical single-GPU instances, polls until both are `active`, and
prints `NODE0_IP` / `NODE1_IP` — export those (the script writes them to `../.env` too).
A Terraform wrapper around the same API calls is in `infra/terraform/` if you want to
practice saying "I provisioned it with Terraform" — it's a thin `null_resource`
wrapper since Lambda doesn't ship an official first-party provider.

### 2. Set up both nodes

Run once per node (Lambda's stock Ubuntu images already have NVIDIA drivers + CUDA):

```bash
scp scripts/00_setup_node.sh ubuntu@$NODE0_IP:~
scp scripts/00_setup_node.sh ubuntu@$NODE1_IP:~
ssh ubuntu@$NODE0_IP 'bash 00_setup_node.sh'
ssh ubuntu@$NODE1_IP 'bash 00_setup_node.sh'
```

This installs Docker + nvidia-container-toolkit, starts `dcgm-exporter` and
`node-exporter` containers on each node, creates a Python venv, and installs
torch/vllm/locust. Also open ports **8000 (vLLM), 9090 (Prometheus), 3000 (Grafana),
9100/9400 (exporters), 29500 (torchrun rendezvous)** in the Lambda firewall rules for
both instances (Cloud dashboard → Firewall).

### 3. NCCL / network sanity check

From your machine, copy and run the distributed test (defaults to a large all-reduce
loop, reports achieved GB/s — a stand-in for `nccl-tests all_reduce_perf`):

```bash
cd ../distributed
scp nccl_bandwidth_test.py launch_distributed.sh ubuntu@$NODE0_IP:~
scp nccl_bandwidth_test.py launch_distributed.sh ubuntu@$NODE1_IP:~

# on node0 (rank 0):
ssh ubuntu@$NODE0_IP "MASTER_ADDR=$NODE0_IP NODE_RANK=0 bash launch_distributed.sh nccl"
# on node1 (rank 1), in a second terminal, run at the same time:
ssh ubuntu@$NODE1_IP "MASTER_ADDR=$NODE0_IP NODE_RANK=1 bash launch_distributed.sh nccl"
```

Both must be launched within the rendezvous timeout window (~60s of each other). Note
the achieved bandwidth — this is your "is the interconnect healthy" number, the exact
check you'd run before trusting any training benchmark on a customer PoC. For the
canonical NCCL test suite instead of this script, see the note at the bottom of
`distributed/nccl_bandwidth_test.py`.

### 4. Multi-node PyTorch DDP training

Same launch pattern, different script:

```bash
ssh ubuntu@$NODE0_IP "MASTER_ADDR=$NODE0_IP NODE_RANK=0 bash launch_distributed.sh ddp"
ssh ubuntu@$NODE1_IP "MASTER_ADDR=$NODE0_IP NODE_RANK=1 bash launch_distributed.sh ddp"
```

Trains a small MLP on synthetic data across both GPUs with `DistributedDataParallel`,
prints per-epoch loss and step time from rank 0.

### 5. Monitoring stack (run on node0)

```bash
scp -r ../monitoring ubuntu@$NODE0_IP:~
ssh ubuntu@$NODE0_IP
cd monitoring
NODE1_IP=<node1's ip> bash start.sh
```

Open `http://$NODE0_IP:3000` (Grafana, default admin/admin, change it). The Prometheus
datasource is pre-provisioned. Import two community dashboards to get real panels fast:
- **NVIDIA DCGM Exporter Dashboard**, Grafana.com ID **12239** (GPU util/mem/power/temp
  per node)
- vLLM's own dashboard JSON: `https://github.com/vllm-project/vllm/blob/main/examples/production_monitoring/grafana.json`
  (request latency, TTFT, throughput, KV-cache usage — scraped straight from vLLM's
  built-in `/metrics`)

### 6. Deploy vLLM

```bash
scp -r ../inference ubuntu@$NODE0_IP:~
ssh ubuntu@$NODE0_IP
cd inference && ../venv/bin/pip install -r requirements.txt 2>/dev/null; MODEL_NAME=Qwen/Qwen2.5-1.5B-Instruct bash vllm_serve.sh
```

Default model is `Qwen/Qwen2.5-1.5B-Instruct` (fits comfortably on a 24GB single GPU,
fast enough for interactive TTFT testing). Swap via `MODEL_NAME`.

Measure time-to-first-token directly:

```bash
python3 ttft_client.py --url http://$NODE0_IP:8000 --prompt "Explain NCCL in two sentences."
```

### 7. Load test

Two options, run either from your machine or node1:

```bash
cd ../load_test

# Option A: Locust (interactive UI, custom TTFT metric)
locust -f locustfile.py --host http://$NODE0_IP:8000
# open http://localhost:8089, set users/spawn rate, watch requests + your custom "ttft_ms" metric

# Option B: vLLM's own benchmark_serving (built-in percentiles for TTFT/ITL/throughput)
bash run_vllm_benchmark.sh $NODE0_IP
```

Watch Grafana while both run — this is the "prove it under load" moment.

### 8. Write up results

Fill in `BENCHMARK_REPORT_TEMPLATE.md` with your numbers (NCCL bandwidth, DDP step
time, TTFT p50/p95, throughput at N concurrent users, GPU utilization from Grafana). In
the interview, being able to walk through *that* document — what you measured, why, and
what you'd tell a customer about their expected bottleneck — is the actual skill this
role is hiring for, more than any single command.

### 9. Tear down

```bash
cd ../infra
./terminate_cluster.sh
```

Confirm in the Lambda Cloud dashboard that both instances are terminated — don't leave
GPUs billing overnight.

## Repo layout

```
lambda-gpu-lab/
  README.md                       this file
  BENCHMARK_REPORT_TEMPLATE.md    fill in after running the lab
  .env.example
  .github/workflows/gpu-lab.yml   full CI/CD pipeline (provision -> benchmark -> teardown)
  infra/
    lambda_cloud_api.sh           curl helpers around Lambda Cloud's REST API
    launch_cluster.sh             manual-path launcher: 2 nodes, waits for active, prints IPs
    terminate_cluster.sh
    terraform/                    Terraform IaC used by both the manual and CI paths
  scripts/
    00_setup_node.sh              run once per node (Docker, exporters, Python venv)
    install_gh_runner.sh          registers a node as a persistent GH Actions runner
  distributed/
    nccl_bandwidth_test.py        multi-node NCCL all-reduce bandwidth probe
    ddp_train.py                  small multi-node DDP training job
    launch_distributed.sh         torchrun wrapper for either script
  monitoring/
    docker-compose.yml            Prometheus + Grafana, host networking (run on node0)
    prometheus.yml.template       rendered by start.sh with node1's IP filled in
    start.sh
    grafana/provisioning/...      pre-wired datasource + dashboard auto-load folder
  inference/
    vllm_serve.sh                 foreground or --background (used by CI)
    ttft_client.py
    requirements.txt
  load_test/
    locustfile.py                 custom TTFT metric via streaming
    run_vllm_benchmark.sh         wraps vLLM's own benchmark_serving.py
```
