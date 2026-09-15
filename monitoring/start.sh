#!/usr/bin/env bash
# Renders prometheus.yml from the template (Prometheus itself has no ${VAR}
# substitution) and brings up Prometheus + Grafana with host networking.
# Usage: NODE1_IP=<node1's ip> bash start.sh
set -euo pipefail
: "${NODE1_IP:?Set NODE1_IP to node1's IP address}"
cd "$(dirname "${BASH_SOURCE[0]}")"

sed "s/__NODE1_IP__/${NODE1_IP}/g" prometheus.yml.template > prometheus.yml
docker compose up -d

echo "Prometheus: http://<node0 ip>:9090"
echo "Grafana:    http://<node0 ip>:3000  (default admin/admin — change it)"
echo "Datasource is pre-provisioned. Import dashboard 12239 (DCGM) and vLLM's"
echo "examples/production_monitoring/grafana.json from grafana.com / the vllm repo."
