# proxmox

> Proxmox VE layer: LXC container profiles and host networking.

## 🗺️ Visual Component Map

```mermaid
graph TD
    scripts["scripts/setup-host.sh"] -->|Configures| PVE["Proxmox VE Host"]
    PVE -->|Runs| LXC100["LXC 100: Docker Host"]
    PVE -->|Runs| LXC101["LXC 101: Media Server"]
    PVE -->|Runs| VM1["VM1 Pop!_OS"]
    PVE -->|Runs| VM2["VM2 Zorin OS"]
    PVE -->|Runs| VM3["VM3 Zorin OS"]
    PVE -->|Runs| VM4["VM4 Windows"]

    NET["proxmox/network/tailscale-routes.sh"] -->|Subnet route| TS["Tailscale Mesh"]
    TS -->|Management| PVE_GUI["Proxmox Web GUI"]
    TS -->|Access| VM1
    TS -->|Access| VM2
    TS -->|Access| VM3
    TS -->|Access| VM4

    LXC100 -->|Hosts| DOCKER["Docker Compose Stack"]
    LXC101 -->|Hosts| PLEX["Plex / Jellyfin"]

    iGPU["Intel UHD 630 iGPU"] -.->|Passthrough| LXC101
```

## 📄 Description and Context

This directory holds Proxmox-specific configuration that lives outside the containers: LXC `.conf` files for LXC 100 and LXC 101, plus the Tailscale subnet-router script used on the bare-metal host.

## 🔗 System Links

* **Parent context:** [README](../README.md)
* **Subsystems:**
  * [lxc](lxc/README.md) — LXC 100 and LXC 101 container configurations
  * [network](network/README.md) — Tailscale subnet routing helper
* **Dependencies:**
  * [HOST-TUNING](../docs/HOST-TUNING.md) — describes the GRUB / sysctl settings Proxmox needs
  * `scripts/setup-host.sh` — applies host-level Proxmox tuning
