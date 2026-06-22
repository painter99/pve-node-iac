Jako Lead Infrastructure Architect a Principal DevOps Engineer jsem provedl detailní analýzu vašeho návrhu. Architektura `pve-node-iac` je koncipována velmi robustně, zejména s ohledem na hardwarová omezení (32GB RAM, consumer SSD) a striktní izolaci zdrojů. 

Níže naleznete kompletní pre-deployment layout, instrukce pro sub-agenty a analýzu edge-cases pro cold-start fázi.

### 1. Repository Directory Structure Design

Pro zajištění idempotence, modularity a dodržení GitOps best practices je struktura repozitáře rozdělena do logických domén. Konfigurace jsou odděleny od exekučních skriptů a šablon.

```text
pve-node-iac/
├── README.md
├── compose.yaml
├── .gitignore
├── docs/
│   ├── architecture.md
│   └── runbooks/
│       └── disaster-recovery.md
├── configs/
│   ├── host/
│   │   ├── sysctl/
│   │   │   └── 99-pve-tuning.conf
│   │   ├── grub/
│   │   │   └── grub-tuning.cfg
│   │   ├── vzdump.conf
│   │   └── datacenter.cfg
│   ├── lxc/
│   │   ├── 100-app-stack.conf
│   │   └── 101-media-server.conf
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   │       └── odoo-proxy.conf
│   └── postgres/
│       └── init-scripts/
│           └── 01-init-pgvector.sql
├── scripts/
│   ├── 01-host-tuning.sh
│   ├── 02-provision-containers.sh
│   └── 03-deploy-stack.sh
└── templates/
    └── cloud-init/
        └── workstation-user-data.yaml
```

### 2. Sub-Agent Instruction Prompts (Task Chaining)

Následující prompty jsou optimalizovány pro menší, vysoce výkonné kódovací modely (např. Qwen 2.5 Coder). Obsahují striktní pravidla pro idempotenci, error handling a validace.

#### Prompt A: Host-Level Tuning & Network Automation
```markdown
# Role
You are an expert Linux Systems Engineer. Generate a strictly idempotent Bash script named `01-host-tuning.sh` for a Proxmox VE 9.x bare-metal host.

# Requirements & Variables
- Target OS: Proxmox VE 9.x (Debian 12 base).
- Variables: `SWAPPINESS=10`, `DIRTY_RATIO=10`, `DIRTY_BG_RATIO=5`, `TAILSCALE_SUBNET="192.168.1.0/24"`.

# Tasks
1. **Sysctl Tuning:** Create `/etc/sysctl.d/99-pve-tuning.conf`. Apply `vm.swappiness`, `vm.dirty_ratio`, and `vm.dirty_background_ratio`. Use `sysctl -p` to apply. Ensure the script checks if the file exists and has the correct content before overwriting.
2. **GRUB Tuning:** Modify `/etc/default/grub` to append `elevator=none` and `mitigations=off` to `GRUB_CMDLINE_LINUX_DEFAULT` for consumer SSD latency optimization. Run `update-grub` ONLY if the file was modified.
3. **VZDump Fleecing:** Write `backup: fleecing=storage=local-lvm` to `/etc/pve/datacenter.cfg` and set `bwlimit: 30000` in `/etc/vzdump.conf`.
4. **Tailscale & Routing:** Check if Tailscale is installed. If not, install it via the official script. Enable IPv4 forwarding in sysctl. Run `tailscale up --advertise-routes=$TAILSCALE_SUBNET --accept-routes` only if the node is not already advertising this route (check via `tailscale status`).

# Constraints
- Use `set -euo pipefail`.
- Every command must be idempotent (e.g., use `grep -q` before appending to files).
- Include explicit exit codes and echo statements for logging.
- Do NOT use `sed -i` without a backup extension or proper regex validation.
```

#### Prompt B: LXC Container Provisioning
```markdown
# Role
You are a Proxmox VE Automation Specialist. Generate an idempotent Bash script named `02-provision-containers.sh` to provision the core application LXC container.

# Requirements & Variables
- CTID: `100`
- Hostname: `odoo-nesting-host`
- Template: `local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst` (assume it's downloaded).
- Resources: `memory=10240`, `cores=4`, `rootfs=local-lvm:30`.
- Network: `name=eth0,bridge=vmbr0,ip=dhcp`.

# Tasks
1. **Pre-flight Check:** Verify if CTID 100 exists using `pct status 100`. If it exists and is running, skip creation. If it exists but is stopped, start it.
2. **Creation:** If CTID 100 does not exist, create it using `pct create` with the specified resources and `unprivileged=1`.
3. **Feature Injection:** Use `pct set 100 -features nesting=1,keyctl=1` to enable Docker nesting and keyring isolation.
4. **Start & Validate:** Start the container (`pct start 100`). Wait for the network interface to get an IP. Ping the container's IP to validate network readiness.

# Constraints
- Use `set -euo pipefail`.
- Use Proxmox CLI tools (`pct`, `pvesm`) exclusively. Do not manipulate `/etc/pve/lxc/*.conf` directly via `echo` or `sed`; always use `pct set`.
- Include a 5-second sleep or polling loop after `pct start` before checking network status.
```

#### Prompt C: Auxiliary Configuration Generation (Nginx & PostgreSQL)
```markdown
# Role
You are a Senior DevOps Engineer specializing in containerized web and database proxies. Generate two configuration files for a Docker Compose stack.

# Task 1: Nginx Reverse Proxy (`configs/nginx/conf.d/odoo-proxy.conf`)
- Create an Nginx server block listening on port 80.
- `server_name` should be `_` (catch-all).
- Proxy pass `/` to `http://web:8069` (Odoo default port).
- Proxy pass `/websocket` to `http://web:8072` (Odoo longpolling).
- **Crucial Headers:** Include `proxy_set_header X-Forwarded-Host $host;`, `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`, `proxy_set_header X-Forwarded-Proto $scheme;`, and `proxy_set_header X-Real-IP $remote_addr;`.
- Set `proxy_read_timeout` and `proxy_connect_timeout` to `7200s` to prevent Odoo long-running reports from timing out.
- Set `client_max_body_size` to `200m` for large ERP attachments.

# Task 2: PostgreSQL Init Script (`configs/postgres/init-scripts/01-init-pgvector.sql`)
- Write a SQL script that executes on database initialization.
- Command: `CREATE EXTENSION IF NOT EXISTS vector;`
- Command: `CREATE EXTENSION IF NOT EXISTS pg_trgm;` (useful for Odoo text search).
- Add comments explaining that this runs only on the first cold start of the PostgreSQL container.

# Constraints
- Output ONLY the raw file contents with clear markdown headers indicating the file path.
- Ensure Nginx syntax is strictly valid for Alpine Nginx.
```

### 3. Initial Architectural Review & Edge Cases

Z pohledu architekta je návrh velmi solidní, ale při cold-startu (např. po výpadku napájení nebo po `reboot` hostitele) narážíme na několik kritických edge-cases, které standardní `depends_on` v Docker Compose nevyřeší.

#### Edge Case 1: Odoo Web Startuje Před Inicializací Schématu a Extenzí
Standardní `depends_on: - db` v Compose pouze čeká na spuštění PostgreSQL *kontejneru*, nikoliv na to, zda je databáze připravena přijímat spojení, nebo zda doběhl `01-init-pgvector.sql`. Pokud se Odoo připojí příliš brzy, spadne na `FATAL: the database system is starting up` nebo selže při pokusu o použití `pgvector` indexů.

**Řešení (Healthcheck Mechanics):**
Musíme implementovat striktní `healthcheck` na úrovni Compose a vynutit `condition: service_healthy`.

```yaml
services:
  db:
    # ... (existing config) ...
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo -d postgres"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 30s # Čas na dokončení init-scripts a vytvoření extenzí

  web:
    # ... (existing config) ...
    depends_on:
      db:
        condition: service_healthy # Klíčové: Odoo počká, dokud pg_isready nevrátí 0
```

#### Edge Case 2: n8n a Whisper API Race Conditions
n8n pipeline se při startu pokouší navázat spojení s databází (pro uložení execution logs) a s Whisper API (pro validaci endpointu). Pokud tyto služby nejsou připraveny, n8n může přejít do stavu `Error` a vyžadovat manuální restart.

**Řešení:**
Přidejte `restart: unless-stopped` (což už v návrhu máte, což je správně), ale pro n8n přidejte také `depends_on` s `service_healthy` na `db`. Pro Whisper API implementujte jednoduchý healthcheck:

```yaml
  whisper-api:
    # ...
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s
      timeout: 5s
      retries: 5
```

#### Edge Case 3: Unprivileged LXC a Docker Named Volumes (UID/GID Mapping)
Zmínil jste, že Docker Named Volumes vyřeší UID/GID mapping. To je pravda, ale při *prvním* startu (cold-start) Docker daemon vytvoří adresář na hostitelském souborovém systému (uvnitř LXC) s UID/GID roota (0:0). Uvnitř kontejneru to ale díky `userns-remap` (nebo standardnímu unprivileged mapování) bude mapováno na `nobody` nebo `65534`. PostgreSQL (UID 999) pak může selhat s `Permission denied` při pokusu o `chown` nebo zápis do `/var/lib/postgresql/data`.

**Řešení (Architektonická korekce):**
Ačkoliv je LXC unprivileged, Docker uvnitř LXC běží jako root (vůči guest OS). Named volumes v Dockeru automaticky provedou `chown` na UID definované v `USER` direktivě Dockerfile (pro PG je to 999). 
**Kritický krok:** Ujistěte se, že v `compose.yaml` u služby `db` **neodstraňujete** výchozího uživatele. Pokud byste přidali `user: "999:999"` do Compose souboru, Docker by ztratil root oprávnění potřebná pro `chown` volume při prvním startu. Nechte Docker, ať si to zřídí sám, pouze se ujistěte, že LXC má dostatek inode a místa na `local-lvm`.

#### Edge Case 4: Tailscale Subnet Routing a RDP
Tailscale na bare-metalu bude routovat `192.168.1.0/24`. Pokud ale KVM VM (např. Windows 11) dostane IP z DHCP až *po* startu Tailscale, nebo pokud se IP změní, Tailscale to nevadí (routuje celou síť). Ale Windows Firewall ve výchozím nastavení blokuje RDP (port 3389) z jiných subnetů než je ten lokální.
**Řešení:** V rámci Cloud-Init nebo provisioning skriptů pro Windows VM musíte přidat PowerShell pravidlo, které povolí RDP z Tailscale subnetu (např. `100.64.0.0/10`), jinak se z venku přes Tailscale na RDP nepřipojíte, i když síťová vrstva bude fungovat.

Tento layout a analýza vám poskytují pevný základ pro implementaci. Skripty vygenerované sub-agenty budou díky striktním promptům idempotentní a bezpečné pro opakované spouštění.