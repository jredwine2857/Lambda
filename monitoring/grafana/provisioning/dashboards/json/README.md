Drop dashboard JSON files here to have Grafana auto-load them on startup instead of
importing by ID through the UI:

- NVIDIA DCGM Exporter Dashboard: download JSON for ID 12239 from grafana.com/grafana/dashboards/12239
- vLLM's dashboard: https://github.com/vllm-project/vllm/blob/main/examples/production_monitoring/grafana.json

Restart the grafana container (or wait ~30s, provisioning polls this folder) after adding files.
