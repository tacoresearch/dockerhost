#!/usr/bin/env bash
set -euo pipefail

# Minimal deploy helper for Proxmox host
# 1) Run Proxmox VM bootstrap script
# 2) Fetch docker-compose.yml
# 3) Start containers with docker compose

TMPDIR="$(mktemp -d /tmp/dockerhost.XXXXXX)"
cleanup() { rc=$?; rm -rf "$TMPDIR"; exit $rc; }
trap cleanup EXIT

echo "==> Starting deploy script"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required but not installed. Aborting." >&2
  exit 1
fi

echo "==> Running Proxmox VM bootstrap script"
curl -fsSL https://raw.githubusercontent.com/tacoresearch/ProxmoxVE/refs/heads/main/vm/docker-vm.sh | bash -s -- "$@"

echo "==> Fetching docker-compose.yml"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/docker-compose.yml"
curl -fsSL "$DOCKER_COMPOSE_URL" -o "$TMPDIR/docker-compose.yml"

echo "==> Determining docker compose command"
COMPOSE_CMD=""
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  fi
fi

if [ -z "$COMPOSE_CMD" ]; then
  echo "ERROR: docker + docker compose are required on this host. Install Docker Engine and Docker Compose." >&2
  exit 2
fi

echo "==> Starting containers with: $COMPOSE_CMD"
pushd "$TMPDIR" >/dev/null
# run in detached mode and remove orphans
$COMPOSE_CMD up -d --remove-orphans
popd >/dev/null

echo "==> Deploy complete"
exit 0
