#!/usr/bin/env bash
# Terminates the two instances recorded in ../.env. Run this every time you're done —
# GPU nodes bill by the hour whether you're using them or not.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lambda_cloud_api.sh
source ../.env

: "${NODE0_ID:?NODE0_ID not set in .env}" "${NODE1_ID:?NODE1_ID not set in .env}"

echo "Terminating node0 ($NODE0_ID) and node1 ($NODE1_ID)..."
terminate_instances "$NODE0_ID" "$NODE1_ID"
echo ""
echo "Verify in the Lambda Cloud dashboard that both show 'terminated'."
