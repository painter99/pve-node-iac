-- 01-init.sql: Idempotent PostgreSQL extensions for the AI/ERP stack.
-- Docker Postgres entrypoint executes this file only on the first volume init.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
