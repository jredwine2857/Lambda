#!/usr/bin/env bash
# Run once on EACH GPU node. Assumes Lambda's stock Ubuntu image (NVIDIA driver + CUDA
# already installed). Installs Docker + nvidia-container-toolkit, starts GPU/host
# metrics exporters, and creates a Python venv with the packages the rest of the lab
# needs.
set -euo pipefail

echo "== Docker + NVIDIA container toolkit =="
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
fi

if dpkg -s nvidia-container-toolkit &>/dev/null; then
  echo "nvidia-container-toolkit already installed by the base image, skipping."
elif grep -rq "nvidia.github.io/libnvidia-container" /etc/apt/sources.list /etc/apt/sources.list.d/ /etc/apt/cloud-init.gpg.d/ 2>/dev/null; then
  # Lambda's stock GPU images pre-configure this apt source via cloud-init. Adding our
  # own copy with a different keyring path breaks apt entirely ("Conflicting values
  # set for option Signed-By") — reuse the existing source instead of duplicating it.
  echo "NVIDIA container toolkit apt source already present, installing package directly."
  sudo apt-get update -y
  sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
else
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  sudo apt-get update -y
  sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
fi

echo "== GPU + host metrics exporters =="
sudo docker rm -f dcgm-exporter node-exporter 2>/dev/null || true
sudo docker run -d --restart unless-stopped --gpus all -p 9400:9400 --cap-add SYS_ADMIN \
  --name dcgm-exporter nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.1-ubuntu22.04
sudo docker run -d --restart unless-stopped -p 9100:9100 \
  --name node-exporter prom/node-exporter:latest

echo "== Python venv =="
sudo apt-get install -y python3-venv build-essential git jq
python3 -m venv ~/venv
source ~/venv/bin/activate
pip install --upgrade pip
# Lambda's A10 image ships a driver that supports up to CUDA 12.8. Unpinned vllm pulls
# a torch built for CUDA 13.0, which fails at CUDA init ("driver too old, found 12080").
# vllm 0.11.0 pins torch==2.8.0, whose wheel is built for CUDA 12.8. Its transformers
# bound is open-ended and transformers 5.x postdates it, so cap that too.
pip install "vllm==0.11.0" "transformers>=4.55.2,<5" locust requests

# device_count() reports the GPU even when CUDA can't initialize, so allocate a tensor
# to force a real init — a bad torch/driver pairing should fail here, not in NCCL.
python - <<'PY'
import torch
torch.zeros(1, device="cuda")
print("torch", torch.__version__, "cuda", torch.version.cuda,
      "gpus", torch.cuda.device_count(), "- CUDA init OK")
PY

echo ""
echo "Setup complete. Exporters: http://$(curl -s ifconfig.me):9400/metrics (DCGM), :9100/metrics (node)."
echo "Activate the venv in new shells with: source ~/venv/bin/activate"
