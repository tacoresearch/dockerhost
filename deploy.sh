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

# ---- VM detection / start / SSH ----
# Configure the expected VM name via env `VM_NAME` if needed; default here is `docker-vm`.
VM_NAME="${VM_NAME:-docker-vm}"
NODE="$(hostname)"
echo "==> Looking for VM named $VM_NAME on node $NODE"

VMID=""
TYPE=""

# Try using pvesh to list VMs/containers and find a matching name/hostname
if command -v pvesh >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  for t in qemu lxc; do
    out=$(pvesh get /nodes/"$NODE"/$t 2>/dev/null || true)
    if [ -n "$out" ]; then
      vmid=$(python3 - <<'PY'
import sys, json
try:
    data = json.load(sys.stdin)
    for item in data:
        if item.get('name') == sys.argv[1] or item.get('hostname') == sys.argv[1]:
            print(item.get('vmid') or item.get('vmid', ''))
            sys.exit(0)
except Exception:
    pass
PY
"$VM_NAME" <<<"$out")
      if [ -n "$vmid" ]; then VMID="$vmid"; TYPE="$t"; break; fi
    fi
  done
fi

# Fallback: search config files in /etc/pve
if [ -z "$VMID" ]; then
  for f in /etc/pve/qemu-server/*.conf; do
    [ -f "$f" ] || continue
    if grep -qE "^name:\s*$VM_NAME\s*$" "$f"; then
      VMID=$(basename "$f" .conf)
      TYPE="qemu"
      break
    fi
  done
fi
if [ -z "$VMID" ]; then
  for f in /etc/pve/lxc/*.conf; do
    [ -f "$f" ] || continue
    if grep -qE "^hostname:\s*$VM_NAME\s*$" "$f"; then
      VMID=$(basename "$f" .conf)
      TYPE="lxc"
      break
    fi
  done
fi

if [ -z "$VMID" ]; then
  echo "WARNING: Could not find VM named $VM_NAME. Skipping VM start/ssh step."
else
  echo "Found $TYPE VM with id $VMID"
  STATUS=""
  if [ "$TYPE" = "qemu" ]; then
    if command -v qm >/dev/null 2>&1; then
      STATUS=$(qm status "$VMID" 2>/dev/null | awk '{print $2}' || true)
    fi
  else
    if command -v pct >/dev/null 2>&1; then
      STATUS=$(pct status "$VMID" 2>/dev/null | awk '{print $2}' || true)
    fi
  fi

  if [ "$STATUS" != "running" ]; then
    echo "Starting $TYPE $VMID..."
    if [ "$TYPE" = "qemu" ]; then
      qm start "$VMID"
    else
      pct start "$VMID"
    fi
    for i in $(seq 1 30); do
      sleep 2
      if [ "$TYPE" = "qemu" ]; then
        s=$(qm status "$VMID" 2>/dev/null | awk '{print $2}' || true)
      else
        s=$(pct status "$VMID" 2>/dev/null | awk '{print $2}' || true)
      fi
      [ "$s" = "running" ] && break
    done
  fi

  # Attempt to discover IP via QEMU/LXC guest agent through pvesh
  VM_IP=""
  if command -v pvesh >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    agent_out=$(pvesh get /nodes/"$NODE"/"$TYPE"/"$VMID"/agent/network-get-interfaces 2>/dev/null || true)
    if [ -n "$agent_out" ]; then
      VM_IP=$(python3 - <<'PY'
import sys, json
try:
    data = json.load(sys.stdin)
    # pvesh may return a dict with 'result' key or a list
    items = data.get('result', data) if isinstance(data, dict) else data
    for iface in items:
        addrs = iface.get('ip-addresses', []) if isinstance(iface, dict) else []
        for addr in addrs:
            ip = addr.get('ip-address')
            t = addr.get('ip-address-type')
            if t == 'ipv4' and ip and not ip.startswith('127.'):
                print(ip)
                sys.exit(0)
except Exception:
    pass
PY
<<<"$agent_out")
    fi
  fi

  if [ -z "$VM_IP" ]; then
    echo "Could not auto-detect VM IP. Please retrieve the VM IP (Proxmox GUI or 'qm agent' output) and SSH manually. Skipping automatic SSH."
  else
    echo "Attempting SSH and remote deploy to root@$VM_IP"
    # Run remote deploy steps on the VM, then drop to an interactive shell
    ssh -t -o StrictHostKeyChecking=no root@"$VM_IP" bash -s <<'REMOTE'
set -euo pipefail

TMPDIR="$(mktemp -d /tmp/dockerhost.XXXXXX)"
cleanup() { rc=$?; rm -rf "$TMPDIR"; exit $rc; }
trap cleanup EXIT

DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/docker-compose.yml"
echo "==> Fetching docker-compose.yml on VM into $TMPDIR"
curl -fsSL "$DOCKER_COMPOSE_URL" -o "$TMPDIR/docker-compose.yml"

COMPOSE_CMD=""
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  fi
fi

if [ -z "$COMPOSE_CMD" ]; then
  echo "ERROR: docker + docker compose are required on this VM. Aborting." >&2
  exit 3
fi

echo "==> Starting containers on VM with: $COMPOSE_CMD"
pushd "$TMPDIR" >/dev/null
# run in detached mode and remove orphans
$COMPOSE_CMD up -d --remove-orphans
popd >/dev/null

echo "==> Remote deploy complete; dropping to interactive shell"
exec bash -l
REMOTE
  fi
fi
echo "==> Deploy complete"
exit 0
