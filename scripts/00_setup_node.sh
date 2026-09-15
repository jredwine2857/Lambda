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
# vLLM pins the exact torch build it needs, so installing torch separately first just
# means downloading multiple GB twice and letting vllm overwrite it (possibly with a
# different CUDA build than the one requested). Install vllm and take its torch.
pip install vllm locust requests
python -c "import torch; print('torch', torch.__version__, 'cuda', torch.version.cuda, 'gpus', torch.cuda.device_count())"

echo ""
echo "Setup complete. Exporters: http://$(curl -s ifconfig.me):9400/metrics (DCGM), :9100/metrics (node)."
echo "Activate the venv in new shells with: source ~/venv/bin/activate"
