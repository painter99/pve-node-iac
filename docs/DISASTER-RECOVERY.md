# Disaster Recovery

> Backup strategy and cold-start recovery for the `pve-node-iac` node.

## 1. Backup configuration

### `/etc/vzdump.conf`

```properties
bwlimit: 30000
compress: zstd
zstd: 4
```

* `bwlimit: 30000` throttles backup streams to ~30 MB/s and protects the SATA bus.
* `compress: zstd` with `zstd: 4` uses multi-threaded compression.

### `/etc/pve/datacenter.cfg`

```properties
backup: fleecing=storage=local-lvm
```

Fleecing decouples running VMs from the backup destination by buffering changed blocks in local-lvm RAM/SSD space.

### Recommended job

Run a nightly snapshot backup from Proxmox:

```bash
vzdump 100 101 --storage <backup-storage> --mode snapshot --compress zstd --notes-template "{{guestname}}-{{node}}" --prune-backups keep-last=7
```

## 2. Cold-start recovery sequence

1. **Host boot** — Proxmox auto-starts LXC 100 and LXC 101 because both have `onboot: 1`.
2. **LXC 100 starts** — Docker daemon starts if `systemctl enable docker` was run inside the container.
3. **Compose stack starts (manual until roadmap item is done)** — run `scripts/deploy-stack.sh` inside LXC 100. There is currently no systemd unit auto-running this script on boot.
4. **Readiness gate** — only the `db` service has a healthcheck; `web` waits for `db` via `condition: service_healthy`. n8n and Nginx start in parallel and rely on `restart: unless-stopped` if upstreams are not ready yet.
5. **Estimated total cold-start ETA:** ~2–4 minutes to full availability after the manual deploy step.

## 3. Power-loss protection

A small consumer UPS is strongly recommended. Without power-loss protection (PLP) on the SSD, an unexpected shutdown can leave the PostgreSQL transaction log in an inconsistent state.

## 4. Runbooks in this repository

* Host re-tuning: `scripts/setup-host.sh`
* Application redeploy: `scripts/deploy-stack.sh`
* Subnet router re-enable: `proxmox/network/tailscale-routes.sh`

## Roadmap

* `systemd` auto-start service for the Docker Compose stack (removes the manual step 3 above).
* Proxmox Backup Server (PBS) target integration.
* UPS-triggered safe shutdown hook.
