#!/usr/bin/env bash
# Deploys the Docker Compose stack inside LXC 100 (unprivileged Docker host).
# Run as root inside the container after Docker service is available.

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "[FAIL] This script must run as root."; exit 99; }

PROJECT_DIR="${PROJECT_DIR:-/opt/pve-node-iac}"
COMPOSE_FILE="$PROJECT_DIR/docker/compose.yaml"
ENV_FILE="$PROJECT_DIR/docker/.env"

log_ok()  { echo "[OK] $*"; }
log_fail(){ echo "[FAIL] $*"; }

# Install Docker Engine from signed APT repository (no curl|sh).
if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    log_ok "Docker Engine installed and started."
else
    log_ok "Docker Engine already installed."
fi

# Ensure compose file exists
if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_fail "Compose file not found: $COMPOSE_FILE"
    exit 1
fi

# Ensure .env exists and contains the required bind IP
if [[ ! -f "$ENV_FILE" ]]; then
    log_fail "Environment file not found: $ENV_FILE (copy from .env.example and set passwords + PROXY_BIND_IP)"
    exit 2
fi

grep -qE '^PROXY_BIND_IP=' "$ENV_FILE" || { log_fail "PROXY_BIND_IP missing in $ENV_FILE"; exit 2; }

# Pull and start stack
cd "$PROJECT_DIR/docker"
docker compose pull
docker compose up -d
log_ok "Stack started with docker compose up -d."

# Wait for PostgreSQL healthcheck (compose allows up to ~130s).
log_ok "Waiting for PostgreSQL healthcheck..."
status=""
for _ in $(seq 1 70); do
    status="$(docker inspect --format '{{.State.Health.Status}}' odoo_postgres 2>/dev/null || true)"
    [[ "$status" == "healthy" ]] && break
    sleep 2
done

if [[ "$status" != "healthy" ]]; then
    log_fail "PostgreSQL did not become healthy."
    exit 3
fi

log_ok "PostgreSQL healthy; pgvector healthcheck passed."
log_ok "Stack deployment verified."
