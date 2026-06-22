#!/usr/bin/env bash
# Proxmox host subnet-router configuration for Tailscale.
# Run as root on the bare-metal Proxmox VE host.

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "[FAIL] This script must run as root."; exit 99; }

TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
# Narrow default: /28 covers 16 addresses. Override with SUBNET_CIDR if a wider range is intentionally required.
SUBNET_CIDR="${SUBNET_CIDR:-192.168.1.0/28}"

if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
    echo "[FAIL] TAILSCALE_AUTH_KEY env variable is required."
    exit 1
fi

SYSCTL_FILE="/etc/sysctl.d/20-network-forwarding.conf"

# Enable IPv4/IPv6 forwarding idempotently
grep -qF "net.ipv4.ip_forward=1" "$SYSCTL_FILE" 2>/dev/null || echo "net.ipv4.ip_forward=1" >> "$SYSCTL_FILE"
grep -qF "net.ipv6.conf.all.forwarding=1" "$SYSCTL_FILE" 2>/dev/null || echo "net.ipv6.conf.all.forwarding=1" >> "$SYSCTL_FILE"
sysctl -p "$SYSCTL_FILE" >/dev/null
echo "[OK] IP forwarding enabled."

# Install Tailscale from signed APT repository (no curl|sh).
if ! command -v tailscale >/dev/null 2>&1; then
    KEYRING="/usr/share/keyrings/tailscale-archive-keyring.gpg"
    REPO_FILE="/etc/apt/sources.list.d/tailscale.list"
    if [[ ! -f "$KEYRING" ]]; then
        curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg -o "$KEYRING"
    fi
    if ! grep -qF "pkgs.tailscale.com/stable/debian" "$REPO_FILE" 2>/dev/null; then
        echo "deb [signed-by=$KEYRING] https://pkgs.tailscale.com/stable/debian bookworm main" > "$REPO_FILE"
    fi
    apt-get update
    apt-get install -y tailscale
    echo "[OK] Tailscale installed from signed repository."
else
    echo "[OK] Tailscale already installed."
fi

# Advertise routes (do not accept inbound subnet routes by default).
if ! tailscale status --json 2>/dev/null | grep -qF "$SUBNET_CIDR"; then
    tailscale up --authkey="$TAILSCALE_AUTH_KEY" --advertise-routes="$SUBNET_CIDR"
    echo "[OK] Tailscale advertising $SUBNET_CIDR."
else
    echo "[OK] Tailscale already advertising $SUBNET_CIDR."
fi

# Validate
if [[ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]]; then
    echo "[FAIL] IPv4 forwarding is not active."
    exit 2
fi

if tailscale status 2>/dev/null | grep -qE "(Stopped|not running)"; then
    echo "[FAIL] Tailscale is not running."
    exit 3
fi

echo "[OK] Tailscale subnet router configured for $SUBNET_CIDR."
