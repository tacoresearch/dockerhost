# deploy.sh

Usage:

Run the script on a Proxmox host over SSH with the familiar curl|bash one-liner:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/deploy.sh)"
```

What the script does:

bash -c "$(curl -fsSL https://raw.githubusercontent.com/tacoresearch/dockerhost/deploy.sh)"
- Downloads `docker-compose.yml` from `https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/docker-compose.yml` into a temporary folder. 

What the script does (flow):

- Runs the Proxmox VM bootstrap helper: `https://raw.githubusercontent.com/tacoresearch/ProxmoxVE/refs/heads/main/vm/docker-vm.sh` to create and provision a VM.
- Detects the created VM by name (see `VM_NAME`, default `docker-vm`), starts it if stopped, and attempts to discover the VM IP via the Proxmox guest agent.
- SSHes into the VM and performs the Docker deployment there: the script fetches `docker-compose.yml` on the VM and runs Docker Compose to start services.
- After remote deployment completes, the script drops to an interactive shell on the VM (so you can inspect logs or run commands).

Prerequisites:

- `curl` must be installed on the Proxmox host (the machine where you run the one-liner).
- You must be able to run Proxmox CLI tools on the Proxmox host (`pvesh`, `qm`, `pct`) — these are used to find and start the VM. If these tools are unavailable the script will still try file-based fallbacks but behavior is reduced.
- The VM bootstrap script will install Docker and Docker Compose inside the VM. Docker/Compose do NOT need to be installed on the Proxmox host.
- Proxmox Guest Agent inside the VM is recommended to allow the script to auto-detect the VM IP. If the guest agent is not available the script will prompt you to retrieve the VM IP manually.

Environment variables:

- `VM_NAME` — optional: name of the VM to look up and start. Default: `docker-vm`.

Behavior notes:

- If the script cannot find the VM by name it prints a warning and will skip the VM start/SSH step.
- If the VM is found but the IP cannot be discovered automatically, the script will print instructions and exit; you can then SSH manually and run the compose commands described below.

Quick manual test (bootstrap only):

Run the Proxmox VM bootstrap script alone to validate VM creation and provisioning:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tacoresearch/ProxmoxVE/refs/heads/main/vm/docker-vm.sh)"
```

After the bootstrap completes, find the VM IP (Proxmox GUI/API or console) and SSH into it to verify Docker and Compose are present:

```bash
ssh root@<vm-ip>
docker --version
docker compose version || docker-compose --version
```

Manual remote deploy (if automatic SSH fails):

```bash
# on your local machine or the Proxmox host:
curl -fsSL https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/docker-compose.yml -o /tmp/docker-compose.yml
# copy to VM or fetch from VM directly and then:
ssh root@<vm-ip> 'bash -s' <<'EOF'
curl -fsSL https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/docker-compose.yml -o /tmp/docker-compose.yml
docker compose -f /tmp/docker-compose.yml up -d --remove-orphans
EOF
```

Security & best-practices:

- The script executes remote content via `curl|bash` — for production usage pin to commit SHAs or use signed artifacts.
- Ensure root SSH access or appropriate keys are available for the VM, or modify the script to use a different user.

If you want, I can:

- Update `deploy.sh` to accept a `--vm-name` CLI flag instead of `VM_NAME` env var, or
- Add commit-SHA pinning for the remote scripts and compose file.
curl -fsSL https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/docker-compose.yml -o /tmp/docker-compose.yml
docker compose -f /tmp/docker-compose.yml up
```

Next step:

The `deploy.sh` will be extended (after testing) with an explicit step that provisions Docker inside the VM and then pulls and runs the `docker-compose.yml` there. For now, the script runs the bootstrap then fetches the compose file and attempts to run it on the machine where the script is executed.

Customization:

- You can download and edit the compose file locally before starting containers if you need to change volumes, ports, or environment values.

Security:

- As with any curl|bash one-liner, you are executing remote code — validate the remote sources and pins (commit SHAs or tags) if you require stronger guarantees.
