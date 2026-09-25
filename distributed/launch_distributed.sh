#!/usr/bin/env bash
# torchrun wrapper for the 2-node scripts in this directory.
# Usage: MASTER_ADDR=<node0 ip> NODE_RANK={0,1} bash launch_distributed.sh {nccl|ddp}
set -euo pipefail

: "${MASTER_ADDR:?Set MASTER_ADDR to the node0 IP (same value on both nodes)}"
: "${NODE_RANK:?Set NODE_RANK to 0 on node0, 1 on node1}"
MASTER_PORT="${MASTER_PORT:-29500}"

case "${1:-}" in
  nccl) SCRIPT="nccl_bandwidth_test.py" ;;
  ddp)  SCRIPT="ddp_train.py" ;;
  *) echo "Usage: $0 {nccl|ddp}" >&2; exit 1 ;;
esac

source ~/venv/bin/activate 2>/dev/null || true

# NCCL picks a network interface on its own and often picks a wrong one — notably
# docker0 (172.17.0.1), which exists on these nodes because the setup script installs
# Docker, and which is unroutable between hosts. The symptom is a silent hang at
# init rather than a clean error, so exclude the local-only interfaces explicitly.
export NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME:-^docker0,lo}"
# Same reasoning for the rendezvous/store traffic.
export GLOO_SOCKET_IFNAME="${GLOO_SOCKET_IFNAME:-$NCCL_SOCKET_IFNAME}"
# Prints the interface and transport NCCL actually chose — this is the output you'd
# screenshot for a customer to prove traffic took the fast path.
export NCCL_DEBUG="${NCCL_DEBUG:-INFO}"

echo "== interfaces on this node =="
ip -brief address 2>/dev/null || true

torchrun \
  --nnodes=2 \
  --nproc_per_node=1 \
  --node_rank="${NODE_RANK}" \
  --master_addr="${MASTER_ADDR}" \
  --master_port="${MASTER_PORT}" \
  "$(dirname "${BASH_SOURCE[0]}")/${SCRIPT}"
