#!/usr/bin/env bash
# Bare-metal Proxmox VE host tuning script.
# Run once as root after Proxmox installation.

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "[FAIL] This script must run as root."; exit 99; }

SWAPPINESS="${SWAPPINESS:-10}"
DIRTY_RATIO="${DIRTY_RATIO:-10}"
DIRTY_BACKGROUND_RATIO="${DIRTY_BACKGROUND_RATIO:-5}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
SUBNET_CIDR="${SUBNET_CIDR:-192.168.1.0/28}"

log_ok()  { echo "[OK] $*"; }
log_fail(){ echo "[FAIL] $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAILSCALE_SCRIPT="$SCRIPT_DIR/../proxmox/network/tailscale-routes.sh"

# Fáze 1: Sysctl memory tuning (atomic rewrite to avoid stale entries)
SYSCTL_MEMORY="/etc/sysctl.d/99-pve-tuning.conf"
cat > "$SYSCTL_MEMORY" <<SYSCTL_EOF
vm.swappiness = ${SWAPPINESS}
vm.dirty_ratio = ${DIRTY_RATIO}
vm.dirty_background_ratio = ${DIRTY_BACKGROUND_RATIO}
SYSCTL_EOF
sysctl -p "$SYSCTL_MEMORY" >/dev/null
[[ "$(sysctl -n vm.swappiness)" == "$SWAPPINESS" ]] || { log_fail "vm.swappiness not applied"; exit 2; }
log_ok "Sysctl memory tuning applied ($SYSCTL_MEMORY)."

# Fáze 2: GRUB kernel parameters
GRUB_FILE="/etc/default/grub"
cp "$GRUB_FILE" "${GRUB_FILE}.bak.$(date +%s)" 2>/dev/null || true

GRUB_PARAMS="intel_iommu=on iommu=pt intel_pstate=active"
for param in $GRUB_PARAMS; do
    if grep -qF "$param" "$GRUB_FILE"; then
        log_ok "GRUB parameter $param already present."
    else
        sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s|\"\$| $param\"|" "$GRUB_FILE"
        log_ok "Added $param to GRUB_CMDLINE_LINUX_DEFAULT."
    fi
done

update-grub >/dev/null
log_ok "GRUB updated. Reboot required for full effect."

# Fáze 3: VZDump + datacenter fleecing (per-line idempotency)
VZDUMP_FILE="/etc/vzdump.conf"
DATACENTER_FILE="/etc/pve/datacenter.cfg"

ensure_line() {
    local file="$1" line="$2"
    grep -qF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

ensure_line "$VZDUMP_FILE" "bwlimit: 30000"
ensure_line "$VZDUMP_FILE" "compress: zstd"
ensure_line "$VZDUMP_FILE" "zstd: 4"
log_ok "VZDump tuning ensured in $VZDUMP_FILE."

ensure_line "$DATACENTER_FILE" "backup: fleecing=storage=local-lvm"
log_ok "Backup fleecing ensured in datacenter.cfg."

# Fáze 4: Tailscale + subnet routing (delegated to the canonical script)
if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
    log_fail "TAILSCALE_AUTH_KEY is required."
    exit 3
fi

if [[ ! -x "$TAILSCALE_SCRIPT" ]]; then
    log_fail "Tailscale script not found or not executable: $TAILSCALE_SCRIPT"
    exit 4
fi

TAILSCALE_AUTH_KEY="$TAILSCALE_AUTH_KEY" SUBNET_CIDR="$SUBNET_CIDR" "$TAILSCALE_SCRIPT"

# Final validation
[[ "$(cat /proc/sys/net/ipv4/ip_forward)" == "1" ]] || { log_fail "IPv4 forwarding not active"; exit 5; }
tailscale status 2>/dev/null | grep -qvE "(Stopped|not running)" || { log_fail "Tailscale is not running"; exit 6; }

log_ok "Host tuning complete. Reboot to activate GRUB changes."
