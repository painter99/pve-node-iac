# pve-node-iac

<p align="center">
  <img src="docs/assets/logo.png" alt="pve-node-iac logo" width="180" height="180">
</p>

> Design and Infrastructure as Code (IaC) artifacts for a proposed single-node Proxmox VE home lab, including host configuration, an unprivileged container layer, and an application deployment stack.

![Status: Superseded by a Headless Workflow — Design Reference](https://img.shields.io/badge/Status-Superseded_by_Headless_Workflow_·_Design_Reference-lightgrey?style=flat-square)
![Project Phase: Design & Feasibility Study](https://img.shields.io/badge/Phase-Design_&_Feasibility_Study-yellow?style=flat-square)
![Personal Project](https://img.shields.io/badge/Type-Personal_·_Home_Lab-blueviolet?style=flat-square)
![No Warranty](https://img.shields.io/badge/Warranty-Use_at_Own_Risk-lightgrey?style=flat-square)

---

> ⚙️ **Status (October 2026): Superseded as a project — retained as a design reference.** This Proxmox VE home-lab design was never deployed or validated on real hardware, and the target hardware was never acquired. The infrastructure need this project was meant to serve is now met differently: a headless, AI-assisted workflow orchestrated through the Agora app — see [agora-pro-setup](https://github.com/painter99/agora-pro-setup). That approach covers the author's current needs; it does not implement every capability this design proposed (for example the multi-VM workstation layer or the media server).

---

## ⚠️ Important Disclaimer

This is a **personal design and learning project**. The proposed setup was never deployed or tested on real hardware, and the repository is kept as a reference, not as a running setup.

- **Educational value:** You may learn from the architecture, decisions, and patterns documented here.
- **Not production-ready:** Code and configuration may contain errors, omissions, or outdated assumptions.
- **No warranty:** There is no guarantee of correctness, safety, or fitness for any purpose.
- **Verify before use:** If you are an IT professional considering any of these patterns, review the canonical IaC files yourself and validate against your own environment.
- **Feedback welcome** but this project is not open for external contributions.

> See [MANUAL.md](MANUAL.md) for the unvalidated reference procedure and [docs/](docs/README.md) for the design rationale.

---

## 🏗️ Core Stack

![Proxmox VE](https://img.shields.io/badge/Proxmox_VE-9.x-E57000?style=flat-square&logo=proxmox&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker&logoColor=white)
![Odoo](https://img.shields.io/badge/Odoo-19.0-7149B6?style=flat-square&logo=odoo&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=flat-square&logo=postgresql&logoColor=white)
![pgvector](https://img.shields.io/badge/Extension-pgvector-4169E1?style=flat-square&logo=postgresql&logoColor=white)
![n8n](https://img.shields.io/badge/n8n-Automation_Pipeline-EA4B71?style=flat-square&logo=n8n&logoColor=white)
![Whisper](https://img.shields.io/badge/faster--whisper-Speech_to_Text-FF6F00?style=flat-square&logo=openai&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-ZeroTrust_VPN-1E222B?style=flat-square&logo=tailscale&logoColor=white)

> For a complete technology catalog, visit the [STACK_BADGES](STACK_BADGES.md) page.

---

## 🗺️ Visual Component Map

```mermaid
graph TD
    EXT["Remote Client / Tailscale User"] -->|Encrypted WireGuard| TS["Tailscale Mesh"]

    subgraph PVE_Host ["Proposed Proxmox VE 9.x Node / Hardware Target"]
        TS -->|Port 8006| PVE_GUI["Proxmox Web GUI"]
        TS -->|Port 80| PROXY["Nginx Reverse Proxy"]

        TS -->|Subnet Router / RDP| VM1["Pop!_OS"]
        TS -->|Subnet Router / RDP| VM2["Zorin OS"]
        TS -->|Subnet Router / RDP| VM3["Zorin OS"]
        TS -->|Subnet Router / RDP| VM4["Windows 10/11"]

        iGPU["Intel UHD 630 iGPU"] -.->|QuickSync Passthrough| PLEX["Plex / Jellyfin"]

        subgraph LXC100 ["LXC 100: Unprivileged Docker Host"]
            direction TB
            PROXY -->|/| WEB["Odoo 19.0 ERP"]
            WEB -->|SQL| DB["PostgreSQL 16 + pgvector"]
            N8N["n8n Automation"] -->|Logs| DB
            N8N -->|STT| WHISPER["faster-whisper CPU"]
        end

        subgraph LXC101 ["LXC 101: Media Server"]
            PLEX
        end
    end
```

---

## 📄 Description and Context

The original design targeted a single-node Proxmox VE home lab on Dell Optiplex 3060-class hardware. It describes a virtual-machine layer alongside an application stack based on Odoo, PostgreSQL, automation, and media services, using unprivileged LXC containers, resource limits, and private-network access. The target hardware was never acquired for this project, and the design has not been validated on a deployed host.

IaC artefacts live as real files in `docker/`, `proxmox/`, and `scripts/`. Each major area keeps its own README so the knowledge graph can scale without overloading this root page.

---

## 🔗 System Links

| Area                               | Description                                                             |
| ---------------------------------- | ----------------------------------------------------------------------- |
| [MANUAL.md](MANUAL.md)             | Unvalidated reference procedure for the original hardware proposal       |
| [docs/](docs/README.md)            | Architecture, hardware, resource budget, host tuning, disaster recovery |
| [docker/](docker/README.md)        | Odoo + AI + PostgreSQL Compose stack (canonical)                        |
| [proxmox/](proxmox/README.md)      | LXC container profiles and Tailscale network configuration              |
| [scripts/](scripts/README.md)      | Host tuning and stack deployment automation                             |
| [archive/](archive/README.md)      | Legacy PoC notes, historical IaC drafts, hardware pivot rationale       |
| [STACK_BADGES.md](STACK_BADGES.md) | Technology badge catalog (shields.io)                                   |
