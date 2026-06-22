# docker/postgres

> PostgreSQL 16 with pgvector for the Odoo + n8n stack.

## 🗺️ Visual Component Map

```mermaid
graph TD
    WEB["Odoo web"] -->|SQL| DB["PostgreSQL db"]
    N8N["n8n automation"] -->|Logs / State| DB

    DB -->|Loads| EXT1["pgvector extension"]
    DB -->|Loads| EXT2["pg_trgm extension"]

    DB -.->|Initialized by| INIT["init/01-init.sql"]

    subgraph Docker ["odoo-network"]
        WEB
        N8N
        DB
    end
```

## 📄 Description and Context

The `db` service runs `pgvector/pgvector:pg16` with a hard 4 GB memory cap and `huge_pages=off`. Initialization scripts in `init/` are mounted read-only into `/docker-entrypoint-initdb.d` and execute only on the first volume creation.

## 🔗 System Links

* **Parent context:** [docker/README](../README.md)
* **Interfaces:**
  * **Input:** SQL connections from `web` (Odoo) and `automation-pipeline` (n8n)
  * **Output:** `pgvector` index support for RAG / semantic search
* **Dependencies:**
  * `init/01-init.sql` — activates `pgvector` and `pg_trgm`
  * `odoo-db-data` named volume — persistent data store
