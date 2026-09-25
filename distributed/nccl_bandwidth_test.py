"""
Multi-node NCCL all-reduce bandwidth probe. Launched via torchrun (see
launch_distributed.sh) with one process per node, one GPU per process — this exercises
the NODE-TO-NODE interconnect specifically (not intra-node NVLink), which is the thing
you actually want to validate before trusting any distributed benchmark on a customer's
cluster.

For the canonical, more rigorous test, build NVIDIA's own nccl-tests
(https://github.com/NVIDIA/nccl-tests) and run all_reduce_perf via `mpirun` across both
nodes — that's what you'd actually cite in a customer-facing report. This script exists
so you can get a real number in minutes without setting up MPI + passwordless SSH first.
"""
import os
import time

import torch
import torch.distributed as dist


def main():
    rank = int(os.environ["RANK"])
    world_size = int(os.environ["WORLD_SIZE"])
    local_rank = int(os.environ["LOCAL_RANK"])

    torch.cuda.set_device(local_rank)
    dist.init_process_group(backend="nccl", rank=rank, world_size=world_size)

    device = torch.device(f"cuda:{local_rank}")
    # 512M floats = 2GB tensor; large enough to be bandwidth-bound, not latency-bound.
    numel = 512 * 1024 * 1024
    tensor = torch.ones(numel, dtype=torch.float32, device=device)

    # warmup
    for _ in range(5):
        dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
    torch.cuda.synchronize()

    iters = 20
    start = time.perf_counter()
    for _ in range(iters):
        dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
    torch.cuda.synchronize()
    elapsed = time.perf_counter() - start

    bytes_per_tensor = tensor.numel() * tensor.element_size()
    # Ring all-reduce moves ~2*(N-1)/N * bytes per rank; report the simpler "algorithm
    # bandwidth" (bytes/time) which is what most quick sanity checks quote.
    algbw_gbps = (bytes_per_tensor * iters) / elapsed / 1e9

    if rank == 0:
        print(f"world_size={world_size} tensor={bytes_per_tensor/1e9:.2f}GB "
              f"iters={iters} total_time={elapsed:.3f}s "
              f"algbw={algbw_gbps:.2f} GB/s")
        print("Sanity check: a healthy 100/200Gbps Ethernet or InfiniBand link between "
              "two single-GPU nodes should land well above a few GB/s here. Numbers "
              "near single-digit MB/s usually mean traffic is falling back to a slow "
              "path (wrong NCCL_SOCKET_IFNAME, no RDMA, or a misconfigured firewall).")

    dist.destroy_process_group()


if __name__ == "__main__":
    main()
