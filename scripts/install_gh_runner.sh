#!/usr/bin/env bash
# Installs and registers this machine as a PERSISTENT GitHub Actions self-hosted
# runner (installed as a systemd service, not --ephemeral). Persistent because this
# node needs to pick up several jobs in sequence (nccl -> ddp -> vllm) during one
# pipeline run, not just one.
#
# Usage: install_gh_runner.sh <repo_url> <registration_token> <label>
set -euo pipefail
REPO_URL="$1"
REG_TOKEN="$2"
LABEL="$3"

# Resolved at run time — a pinned version goes stale and GitHub can refuse to register
# a runner that's too old. Falls back to a known-good version if the API call fails.
# Parsed in pure bash on purpose: `curl | grep -m1 | sed` both dies under pipefail
# (grep exits early, curl fails writing) and mis-parses the single-line JSON.
if [[ -z "${RUNNER_VERSION:-}" ]]; then
  latest="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest || true)"
  if [[ $latest =~ \"tag_name\":[[:space:]]*\"v?([^\"]+)\" ]]; then
    RUNNER_VERSION="${BASH_REMATCH[1]}"
  fi
fi
RUNNER_VERSION="${RUNNER_VERSION:-2.337.0}"
echo "Installing GitHub Actions runner v${RUNNER_VERSION}"

mkdir -p ~/actions-runner && cd ~/actions-runner
if [[ ! -f config.sh ]]; then
  curl -fsSL -o runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  tar xzf runner.tar.gz
fi

./config.sh --unattended --url "$REPO_URL" --token "$REG_TOKEN" --labels "$LABEL" --name "$LABEL" --replace

sudo ./svc.sh install ubuntu
sudo ./svc.sh start
