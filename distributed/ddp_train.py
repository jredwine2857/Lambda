"""
Small multi-node DistributedDataParallel training job: an MLP fit to synthetic
regression data, one process per node, one GPU per process. The point isn't the model —
it's exercising the full DDP path (gradient all-reduce every step) across the real
network link between your two Lambda nodes, and reporting step time so you have a
concrete "training throughput" number to go with the raw NCCL bandwidth number.
"""
import os
import time

import torch
import torch.distributed as dist
import torch.nn as nn
from torch.nn.parallel import DistributedDataParallel as DDP


class MLP(nn.Module):
    def __init__(self, dim=4096, hidden=8192):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(dim, hidden), nn.ReLU(),
            nn.Linear(hidden, hidden), nn.ReLU(),
            nn.Linear(hidden, dim),
        )

    def forward(self, x):
        return self.net(x)


def main():
    rank = int(os.environ["RANK"])
    world_size = int(os.environ["WORLD_SIZE"])
    local_rank = int(os.environ["LOCAL_RANK"])

    torch.cuda.set_device(local_rank)
    dist.init_process_group(backend="nccl", rank=rank, world_size=world_size)
    device = torch.device(f"cuda:{local_rank}")

    dim = 4096
    model = MLP(dim=dim).to(device)
    model = DDP(model, device_ids=[local_rank])
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-4)

    batch_size = 64
    steps = 50
    step_times = []

    for step in range(steps):
        x = torch.randn(batch_size, dim, device=device)
        y = torch.randn(batch_size, dim, device=device)

        torch.cuda.synchronize()
        t0 = time.perf_counter()

        optimizer.zero_grad()
        out = model(x)
        loss = nn.functional.mse_loss(out, y)
        loss.backward()  # DDP all-reduces gradients here
        optimizer.step()

        torch.cuda.synchronize()
        step_times.append(time.perf_counter() - t0)

        if rank == 0 and step % 10 == 0:
            print(f"step={step:03d} loss={loss.item():.4f} step_time={step_times[-1]*1000:.1f}ms")

    if rank == 0:
        steady_state = step_times[10:]  # drop warmup steps
        avg_ms = sum(steady_state) / len(steady_state) * 1000
        print(f"\nworld_size={world_size} avg_step_time={avg_ms:.1f}ms "
              f"(steps 10-{steps}, batch_size={batch_size} per rank, "
              f"global_batch={batch_size*world_size})")

    dist.destroy_process_group()


if __name__ == "__main__":
    main()
