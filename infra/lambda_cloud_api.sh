#!/usr/bin/env bash
# Thin curl wrapper around the Lambda Cloud REST API (https://cloud.lambdalabs.com/api/v1/docs).
# Source this file for the functions, or run it directly with a subcommand:
#   ./lambda_cloud_api.sh list-types
#   ./lambda_cloud_api.sh list-instances
set -euo pipefail

: "${LAMBDA_API_KEY:?Set LAMBDA_API_KEY (source your .env first)}"
API_BASE="https://cloud.lambdalabs.com/api/v1"

_curl() {
  curl -sS -u "${LAMBDA_API_KEY}:" "$@"
}

list_types() {
  _curl "${API_BASE}/instance-types" | jq -r '
    .data | to_entries[] |
    select(.value.regions_with_capacity_available | length > 0) |
    "\(.key)\t\(.value.instance_type.gpu_description)\t\(.value.regions_with_capacity_available | map(.name) | join(","))"
  ' | column -t -s $'\t'
}

list_instances() {
  _curl "${API_BASE}/instances" | jq -r '
    .data[] | "\(.id)\t\(.name)\t\(.ip // "pending")\t\(.status)\t\(.instance_type.name)"
  ' | column -t -s $'\t'
}

launch_instance() {
  local name="$1"
  _curl -X POST "${API_BASE}/instance-operations/launch" \
    -H 'Content-Type: application/json' \
    -d "{
      \"region_name\": \"${REGION}\",
      \"instance_type_name\": \"${INSTANCE_TYPE}\",
      \"ssh_key_names\": [\"${SSH_KEY_NAME}\"],
      \"name\": \"${name}\"
    }"
}

get_instance() {
  local id="$1"
  _curl "${API_BASE}/instances/${id}"
}

terminate_instances() {
  # accepts one or more instance IDs
  local ids_json
  ids_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
  _curl -X POST "${API_BASE}/instance-operations/terminate" \
    -H 'Content-Type: application/json' \
    -d "{\"instance_ids\": ${ids_json}}"
}

# Allow `./lambda_cloud_api.sh <subcommand>` usage in addition to sourcing.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    list-types) list_types ;;
    list-instances) list_instances ;;
    *) echo "Usage: $0 {list-types|list-instances}" >&2; exit 1 ;;
  esac
fi
