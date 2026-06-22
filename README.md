# pve-node-iac

> Infrastructure as Code (IaC) repository for provisioning, tuning, and orchestrating a Proxmox VE single-node home lab environment. This repository directly manages the bare-metal host configuration, the unprivileged nesting container layer, and the application deployment stack.

![Status: Pre-Alpha — Theoretical Research Phase](https://img.shields.io/badge/Status-Pre--Alpha_·_Research_Phase-orange?style=flat-square)
![Project Phase: Design & Feasibility Study](https://img.shields.io/badge/Phase-Design_&_Feasibility_Study-yellow?style=flat-square)
![Personal Project](https://img.shields.io/badge/Type-Personal_·_Home_Lab-blueviolet?style=flat-square)
![No Warranty](https://img.shields.io/badge/Warranty-Use_at_Own_Risk-lightgrey?style=flat-square)

---

## ⚠️ Important Disclaimer

This is a **personal / home lab project**. It is in a **pre-alpha research and design phase** — nothing here has been tested on real hardware yet.

- **Educational value:** You may learn from the architecture, decisions, and patterns documented here.
- **Not production-ready:** Code and configuration may contain errors, omissions, or outdated assumptions.
- **No warranty:** There is no guarantee of correctness, safety, or fitness for any purpose.
- **Verify before use:** If you are an IT professional considering any of these patterns, review the canonical IaC files yourself and validate against your own environment.
- **Feedback welcome** but this project is not open for external contributions.

> See [MANUAL.md](MANUAL.md) for the deployment tutorial and [docs/](docs/README.md) for architectural rationale.

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

    subgraph PVE_Host ["Proxmox VE 9.x Node / Dell Optiplex"]
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

A single-node Proxmox VE home lab on a Dell Optiplex 3060 (i5-9500T, 32 GB RAM, 480 GB SSD). The architecture consolidates a family multi-tenant KVM workstation layer with an AI-augmented ERP stack (Odoo 19 + PostgreSQL 16 + pgvector + n8n + faster-whisper) into unprivileged LXC nesting containers with strict resource caps and zero-exposure networking via Tailscale.

IaC artefacts live as real files in `docker/`, `proxmox/`, and `scripts/`. Each major area keeps its own README so the knowledge graph can scale without overloading this root page.

---

## 🔗 System Links

| Area                               | Description                                                             |
| ---------------------------------- | ----------------------------------------------------------------------- |
| [MANUAL.md](MANUAL.md)             | English step-by-step deployment tutorial (Dell Optiplex)                |
| [docs/](docs/README.md)            | Architecture, hardware, resource budget, host tuning, disaster recovery |
| [docker/](docker/README.md)        | Odoo + AI + PostgreSQL Compose stack (canonical)                        |
| [proxmox/](proxmox/README.md)      | LXC container profiles and Tailscale network configuration              |
| [scripts/](scripts/README.md)      | Host tuning and stack deployment automation                             |
| [archive/](archive/README.md)      | Legacy PoC notes, historical IaC drafts, hardware pivot rationale       |
| [STACK_BADGES.md](STACK_BADGES.md) | Technology badge catalog (shields.io)                                   |
