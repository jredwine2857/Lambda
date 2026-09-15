#!/usr/bin/env bash
# Launches 2 identical Lambda Cloud GPU instances, waits until both are active,
# and writes their IPs back into ../.env. Costs money the moment it runs.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lambda_cloud_api.sh

: "${INSTANCE_TYPE:?}" "${REGION:?}" "${SSH_KEY_NAME:?}"

echo "Launching node0 and node1 (${INSTANCE_TYPE} in ${REGION})..."
resp0=$(launch_instance "gpu-lab-node0")
resp1=$(launch_instance "gpu-lab-node1")

id0=$(echo "$resp0" | jq -r '.data.instance_ids[0] // empty')
id1=$(echo "$resp1" | jq -r '.data.instance_ids[0] // empty')

if [[ -z "$id0" || -z "$id1" ]]; then
  echo "Launch failed. Responses:" >&2
  echo "$resp0" >&2
  echo "$resp1" >&2
  exit 1
fi

echo "node0 id=$id0, node1 id=$id1 — polling for active status (checks every 15s)..."

get_ip() {
  local id="$1"
  get_instance "$id" | jq -r '.data.ip // empty'
}
get_status() {
  local id="$1"
  get_instance "$id" | jq -r '.data.status // empty'
}

for i in $(seq 1 40); do
  s0=$(get_status "$id0"); s1=$(get_status "$id1")
  echo "  [$i] node0=$s0 node1=$s1"
  if [[ "$s0" == "active" && "$s1" == "active" ]]; then break; fi
  sleep 15
done

ip0=$(get_ip "$id0"); ip1=$(get_ip "$id1")

if [[ -z "$ip0" || -z "$ip1" ]]; then
  echo "Timed out waiting for instances to become active. Check the Lambda Cloud dashboard." >&2
  exit 1
fi

echo ""
echo "node0: id=$id0 ip=$ip0"
echo "node1: id=$id1 ip=$ip1"

ENV_FILE="../.env"
if [[ -f "$ENV_FILE" ]]; then
  sed -i.bak -e "s/^NODE0_IP=.*/NODE0_IP=${ip0}/" \
             -e "s/^NODE1_IP=.*/NODE1_IP=${ip1}/" \
             -e "s/^NODE0_ID=.*/NODE0_ID=${id0}/" \
             -e "s/^NODE1_ID=.*/NODE1_ID=${id1}/" "$ENV_FILE"
  echo "Wrote IPs/IDs into $ENV_FILE"
fi

echo ""
echo "Wait ~30s for SSH to come up, then: ssh ubuntu@${ip0}"
echo "Remember to run ./terminate_cluster.sh when you're done for the day."
