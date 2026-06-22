# Resource Budget

> RAM allocation for the `pve-node-iac` single node (32 GB physical RAM).

The table below reflects the fixed KVM RAM assignments, the LXC cgroup ceilings and the Docker Compose memory caps.

| Target / Service               | Type          | Architecture Role              | RAM Limit | Storage / I/O Tuning               |
| :----------------------------- | :------------ | :----------------------------- | :-------- | :--------------------------------- |
| **Proxmox Host**               | Bare-Metal    | Hypervisor & System Cache      | ~2.0 GB   | Host OS baseline + Tailscale       |
| **User Workstation 1**         | KVM VM        | Pop!_OS (COSMIC/GNOME) via RDP | 5.0 GB    | 70 GB Thin Provisioned             |
| **User Workstation 2**         | KVM VM        | Zorin OS via RDP / RustDesk    | 5.0 GB    | 50 GB Thin Provisioned             |
| **User Workstation 3**         | KVM VM        | Zorin OS via RDP / RustDesk    | 5.0 GB    | 50 GB Thin Provisioned             |
| **User Workstation 4**         | KVM VM        | Windows 10/11 Pro via RDP      | 6.0 GB    | 80 GB Thin Provisioned             |
| **App & AI Stack (LXC 100)**   | LXC Container | Nesting Docker Engine Core     | ~10.0 GB  | Named Volumes on Host rootfs       |
| **Smart TV / Media (LXC 101)** | LXC Container | Plex/Jellyfin Media Server     | ~2.0 GB   | iGPU UHD 630 QuickSync Passthrough |

## Ceilings and overcommit

* **LXC 100 ceiling:** `memory: 10240` (10 GB) with `swap: 0`.
* **Docker Compose memory cap (inside LXC 100):** 9.0 GB total for all services (`db` 4 GB, `web` 2.5 GB, `whisper-api` 1 GB, `automation-pipeline` 1 GB, `proxy` 512 MB). The remaining ~1 GB inside the 10 GB LXC ceiling is left for the Docker daemon and OS overhead.
* **LXC 101 ceiling:** `memory: 2048` (2 GB) with `swap: 0`.

Static allocations sum to ~35 GB on a 32 GB node. This is intentional overcommit: not all family VMs are expected to hit their full allocation simultaneously, and KVM balloon drivers plus `vm.swappiness=10` on the host absorb short spikes. Treat the table as hard ceilings, not guaranteed concurrent headroom.

## Proxmox LXC configuration

* LXC 100: `memory: 10240`, `swap: 0`, `cores: 2`, `onboot: 1`
* LXC 101: `memory: 2048`, `swap: 0`, `cores: 2`, `onboot: 1`

See also:

* Container configs in `proxmox/lxc/`
* Tuning details: [HOST-TUNING](HOST-TUNING.md)
