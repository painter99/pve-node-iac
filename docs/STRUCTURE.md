# Repository Structure

> Canonical tree of `pve-node-iac` after Phase 2 materialization.

```text
pve-node-iac/
├── README.md                          # Root hub — PKM navigation, global topology
├── .gitignore                         # Ignores .env, backups, local runtime data
├── MANUAL.md                          # English step-by-step deployment tutorial (Dell Optiplex)
├── stack_badges.md                    # Technology badge catalog (shields.io)
│
├── docs/
│   ├── README.md                      # Documentation index (mindmap)
│   ├── STRUCTURE.md                   # This file — canonical repository tree
│   ├── ARCHITECTURE.md                # Design decisions, sandbox strategy, topology
│   ├── HARDWARE.md                    # Dell Optiplex 3060 hardware profile
│   ├── RESOURCE-BUDGET.md             # 32 GB RAM allocation matrix, OOM prevention
│   ├── HOST-TUNING.md                 # GRUB, sysctl, LXC kernel tweaks
│   └── DISASTER-RECOVERY.md           # VZDump, fleecing, cold-start recovery
│
├── docker/
│   ├── README.md                      # Compose stack overview (micro topology)
│   ├── compose.yaml                   # Odoo 19 + AI + PostgreSQL stack (canonical)
│   ├── .env.example                   # Secrets template — copy to .env before deploy
│   ├── odoo_addons/                   # Empty mount target for custom Odoo addons
│   │   └── .gitkeep
│   ├── nginx/
│   │   ├── README.md                  # Nginx proxy overview (interface map)
│   │   └── nginx.conf                 # Zero-exposure reverse proxy (/ + /websocket)
│   └── postgres/
│       ├── README.md                  # PostgreSQL + pgvector overview
│       └── init/
│           ├── README.md              # Init script overview
│           └── 01-init.sql            # Idempotent CREATE EXTENSION vector + pg_trgm
│
├── proxmox/
│   ├── README.md                      # Proxmox layer overview (LXC + network)
│   ├── lxc/
│   │   ├── README.md                  # LXC 100/101 profile map
│   │   ├── 100-docker-host.conf       # Unprivileged nesting container (onboot, swap:0)
│   │   └── 101-media-server.conf      # Plex/Jellyfin with iGPU cgroup2 passthrough
│   └── network/
│       ├── README.md                  # Tailscale subnet routing overview
│       └── tailscale-routes.sh        # Idempotent Tailscale install + advertise-routes
│
├── scripts/
│   ├── README.md                      # Deployment flow overview
│   ├── setup-host.sh                  # Bare-metal tuning (sysctl, GRUB, VZDump, Tailscale)
│   └── deploy-stack.sh                # Docker install + compose up + healthcheck gate
│
└── archive/                           # Historical reference — do not modify
    ├── README.md                      # Archive mindmap (X230 PoC, IaC1/IaC2, pivot notes)
    ├── notes.md                       # Working notes, AI model role matrix
    ├── RM.md                          # Legacy requirements matrix (superseded by docs/)
    ├── zahajovací_prompt.md           # Original session initiation prompt
    ├── IaC1.md                        # First IaC spec draft (sub-agent prompts A/B/C)
    ├── IaC2.md                        # Second IaC spec draft (simpler prompts)
    ├── erp_server_proxmox_stack.md    # Legacy X230 Proxmox PoC manual
    └── erp_server_debian_stack.md     # Legacy X230 KVM-on-Debian PoC script set
```
