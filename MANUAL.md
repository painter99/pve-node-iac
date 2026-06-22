# Deployment Manual: PVE 9.2 on Dell Optiplex 3060

This manual defines the exact steps for deploying, low-level tuning, and securing the Proxmox VE 9.2.2 hypervisor on Dell Optiplex 3060 (Micro/SFF) edge hardware. The goal is maximum efficiency of the 6-core CPU, strict management of 32 GB RAM, and a "Zero Exposure" security policy for a remote AI-ready ERP system (Odoo 19 + PostgreSQL 16).

> All IaC artefacts referenced below are materialized as real files in this repository. This manual tells you **where to place each file**. Do not copy-paste code from older notes — always use the canonical files in `docker/`, `proxmox/`, and `scripts/`.

---

## 1. Host-Level Configuration (Proxmox VE 9.2.2 CLI)

### 1.1. Kernel tuning via GRUB

Open the GRUB configuration:

```bash
nano /etc/default/grub
```

Edit the following line:

```properties
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt intel_pstate=active"
```

- `intel_iommu=on iommu=pt`: enables HW virtualization for PCIe devices (e.g. iGPU for Plex/Jellyfin).
- `intel_pstate=active`: modern CPU frequency management.

Apply the changes (for ext4/LVM-Thin systems using GRUB):

```bash
update-grub
```

### 1.2. RAM, LVM-Thin, and SSD tuning

- **Do NOT use ZFS** — you are using ext4 on LVM-Thin; no ARC configuration is needed.
- **Hugepages**: Not needed for the Docker/LXC stack. PostgreSQL in unprivileged LXC runs with `huge_pages=off`.
- **SSD tuning**: For modern SSDs, reduce swappiness and dirty_ratio:

```bash
nano /etc/sysctl.d/99-pve-tuning.conf
```

Insert the configuration (also managed idempotently by `scripts/setup-host.sh`):

```ini
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
```

Apply without reboot:

```bash
sysctl --system
```

### 1.3. Reboot the host

```bash
reboot
```

---

## 2. Virtual Machines and LXC Containers

### 2.1. KVM VMs (Workstations)

- **CPU**: 2–4 cores as needed (set type to `host` for instruction sets).
- **RAM**: 5–6 GB per VM.
- **Storage**: Thin provisioned, VirtIO SCSI Single, async interface set to `io_uring`, enable `discard` (TRIM).
- **Network**: VirtIO, multiqueue 2, PVE firewall enabled.

### 2.2. LXC 100 (Unprivileged, Docker Engine Core)

The canonical configuration is in this repository at `proxmox/lxc/100-docker-host.conf`. Copy it to the Proxmox host:

```bash
cp proxmox/lxc/100-docker-host.conf /etc/pve/lxc/100.conf
```

Contents:

```properties
unprivileged: 1
features: nesting=1,keyctl=1
onboot: 1
memory: 10240
swap: 0
cores: 2
```

- `onboot: 1` ensures the container auto-starts after a host reboot.
- `swap: 0` prevents swap-thrashing for the PostgreSQL workload.
- 10 GB RAM limit gives sufficient headroom for the Docker daemon and OS page cache.

### 2.3. LXC 101 (Media Server)

The canonical configuration is at `proxmox/lxc/101-media-server.conf`:

```bash
cp proxmox/lxc/101-media-server.conf /etc/pve/lxc/101.conf
```

Contents:

```properties
unprivileged: 1
features: nesting=1
onboot: 1
memory: 2048
swap: 0
cores: 2
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

- iGPU passthrough maps `/dev/dri/renderD128` for QuickSync hardware transcoding in Plex/Jellyfin.
- RAM capped at 2 GB, swap disabled.

---

## 3. Docker Stack (LXC 100)

### 3.1. Reverse proxy Nginx

The canonical Nginx configuration is at `docker/nginx/nginx.conf`. Inside LXC 100, place it in the project directory so the Compose volume mount resolves it:

```bash
# The compose.yaml mounts ./nginx/nginx.conf — keep this path structure.
ls docker/nginx/nginx.conf
```

This config:

- Proxies HTTP `/` to Odoo on `web:8069`.
- Proxies `/websocket` to Odoo with WebSocket upgrade headers (`proxy_http_version 1.1`).
- Sets `proxy_connect_timeout 30s` (connection establishment) and `proxy_read_timeout 720s` (long-running Odoo reports).
- Does NOT expose the database port (Zero Exposure Topology).

### 3.2. `compose.yaml`

The canonical Compose file is at `docker/compose.yaml`. **Do not edit the inline copy in any other document** — this is the single source of truth.

Key properties of the production stack:

- **Secrets**: passwords are `${POSTGRES_PASSWORD}` and `${PASSWORD}`, loaded from `docker/.env`.
- **Database**: `POSTGRES_DB=odoo` (matches the healthcheck and Odoo convention).
- **Healthcheck**: `db` runs `pg_isready` + `pgvector` extension check; `web` starts only after `db` is healthy (`condition: service_healthy`).
- **Zero exposure**: only Nginx publishes port 80, bound to `${PROXY_BIND_IP}` (your Tailscale/LXC IP). Whisper (`8000`) and n8n (`5678`) are internal only.
- **Memory caps**: `db` 4 GB, `web` 2.5 GB, `whisper-api` 1 GB, `automation-pipeline` 1 GB, `proxy` 512 MB — total 9 GB inside the 10 GB LXC ceiling.

Before first deploy, create the `.env` file:

```bash
cp docker/.env.example docker/.env
nano docker/.env
```

Set at minimum:

```
POSTGRES_PASSWORD=<your-real-password>
PASSWORD=<same-value-as-above>
PROXY_BIND_IP=<lxc-100-tailscale-ip>
```

### 3.3. PostgreSQL init script

The canonical init script is at `docker/postgres/init/01-init.sql`:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

This runs automatically on first volume creation via the Docker entrypoint. No manual `CREATE EXTENSION` is needed.

### 3.4. Start the stack

Either run the deployment script (recommended):

```bash
./scripts/deploy-stack.sh
```

Or manually inside LXC 100:

```bash
cd /opt/pve-node-iac/docker
docker compose up -d
```

---

## 4. Backup and Data Protection

### 4.1. Backup configuration (PVE Host)

These settings are applied idempotently by `scripts/setup-host.sh`. For manual setup:

`/etc/vzdump.conf`:

```properties
bwlimit: 30000
compress: zstd
zstd: 4
```

`/etc/pve/datacenter.cfg`:

```properties
backup: fleecing=storage=local-lvm
```

Fleecing decouples running VMs from the backup destination by buffering changed blocks in local-lvm RAM/SSD space.

### 4.2. Recommended nightly backup

```bash
vzdump 100 101 --storage <backup-storage> --mode snapshot --compress zstd --notes-template "{{guestname}}-{{node}}" --prune-backups keep-last=7
```

Schedule this in Proxmox GUI: Datacenter → Backup at 02:00.

---

## 5. Network Security and VPN

- Install Tailscale directly on the Proxmox bare-metal host using `proxmox/network/tailscale-routes.sh` (or `scripts/setup-host.sh` which calls it).
- The default advertised subnet is `192.168.1.0/28` (narrow — 16 addresses). Override with `SUBNET_CIDR` if a wider range is intentionally required.
- `--accept-routes` is NOT enabled by default (no inbound subnet routes from other nodes).
- All remote access to the Proxmox Web GUI (`:8006`) and the Docker proxy (`:80`) must go exclusively through the encrypted Tailscale IP.

---

## 6. Monitoring and Maintenance

- Regularly check storage I/O performance: `pveperf /var/lib/vz`
- Monitor SSD wear: `smartctl -a /dev/sda`
- Monitor CPU temperatures under load (especially during local Whisper audio transcription).

---

## RAM Budget and Memory Management (32 GB RAM Total)

| Component / VM / LXC         | RAM Limit      | Risk Strategy                      |
| ---------------------------- | -------------- | ---------------------------------- |
| Proxmox Host                 | ~2 GB          | Fixed hypervisor baseline          |
| KVM VM 1–4 (Family)          | 21 GB          | Fixed KVM allocation (overcommit)  |
| LXC 100 (Docker Engine Core) | 10 GB          | Capped in PVE (cgroupsv2, swap: 0) |
| LXC 101 (Media Server)       | ~2 GB          | Capped in PVE (swap: 0)            |
| **Host safety reserve**      | **overcommit** | Balloon drivers + low swappiness   |

> Static allocations sum to ~35 GB on a 32 GB node. This is intentional overcommit: not all family VMs are expected to hit their full allocation simultaneously. See `docs/RESOURCE-BUDGET.md` for details.
