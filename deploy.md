# deploy.sh

Usage:

Run the script on a Proxmox host over SSH with the familiar curl|bash one-liner:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tacoresearch/dockerhost/deploy.sh)"
```

What the script does:

- Executes the Proxmox VM bootstrap helper: `https://raw.githubusercontent.com/tacoresearch/ProxmoxVE/refs/heads/main/vm/docker-vm.sh`.
- Downloads `docker-compose.yml` from `https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/docker-compose.yml` into a temporary folder. 

-The next script installs Docker and Docker Compose inside that VM.

- Download and runs (#insert script here)

- Starts the services with Docker Compose (`docker compose up -d` or `docker-compose up -d`), using `--remove-orphans`.

Prerequisites:

- `curl` must be installed on the Proxmox host (the machine where you run the one-liner).
- Docker is required on the VM.

Notes and safety:

- The script uses a temporary working directory under `/tmp` and cleans it up on exit.
- It uses `set -euo pipefail` to fail fast on errors.
- The script runs the remote Proxmox bootstrap script unprivileged via the current shell; review that remote script before running in production.


Troubleshooting:

- If the script exits with "curl is required", install `curl` on the Proxmox host and retry.

- If you need to validate the bootstrap and VM first, use the Quick test steps below.

Quick test (run the bootstrap only):

Run the Proxmox VM bootstrap script directly to create the VM and install Docker there:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tacoresearch/ProxmoxVE/refs/heads/main/vm/docker-vm.sh)"
```

After the script completes, determine the VM's IP (via Proxmox GUI/API or console) and SSH into it to verify Docker and Compose are available:

```bash
ssh root@<vm-ip>
docker --version
docker compose version || docker-compose --version
```

To inspect compose output or errors from the compose file without running the deploy script:

```bash
curl -fsSL https://raw.githubusercontent.com/tacoresearch/dockerhost/refs/heads/main/docker-compose.yml -o /tmp/docker-compose.yml
docker compose -f /tmp/docker-compose.yml up
```

Next step:

The `deploy.sh` will be extended (after testing) with an explicit step that provisions Docker inside the VM and then pulls and runs the `docker-compose.yml` there. For now, the script runs the bootstrap then fetches the compose file and attempts to run it on the machine where the script is executed.

Customization:

- You can download and edit the compose file locally before starting containers if you need to change volumes, ports, or environment values.

Security:

- As with any curl|bash one-liner, you are executing remote code — validate the remote sources and pins (commit SHAs or tags) if you require stronger guarantees.
