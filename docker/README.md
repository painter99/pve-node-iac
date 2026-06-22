# docker

> Consolidated Odoo 19 + AI + PostgreSQL Docker Compose stack.

## 🗺️ Visual Component Map

```mermaid
graph TD
    EXT["Client via Tailscale"] -->|Port 80| PROXY["Nginx Reverse Proxy"]

    PROXY -->|/| WEB["Odoo 19.0 ERP"]
    PROXY -->|/websocket| WEB

    WEB -->|SQL| DB["PostgreSQL 16 + pgvector"]

    N8N["n8n Automation"] -->|Logs / State| DB
    N8N -->|Audio STT| WHISPER["faster-whisper CPU"]

    subgraph Internal_Network ["odoo-network bridge"]
        PROXY
        WEB
        DB
        N8N
        WHISPER
    end
```

## 📄 Description and Context

This folder contains the production-quality Compose definition that runs inside the unprivileged LXC 100 container. Only Nginx exposes a port (`80/tcp`); Whisper and n8n remain internal and communicate through the `odoo-network` bridge.

## 🔗 System Links

* **Parent context:** [README](../README.md)
* **Dependencies:**
  * [RESOURCE-BUDGET](../docs/RESOURCE-BUDGET.md) — memory limits assigned here
  * [HOST-TUNING](../docs/HOST-TUNING.md) — kernel flags that allow nesting inside LXC 100
  * `nginx/nginx.conf` — single ingress point
  * `postgres/init/01-init.sql` — database bootstrap including `pgvector`
