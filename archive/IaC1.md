# 🏗️ Pre-Deployment Architektonický Plán — `pve-node-iac`

Následující analýza představuje kompletní pre-work layout repozitáře před jakýmkoliv zásahem na bare-metal hardwaru. Vše je strukturováno pro GitOps pipeline a idempotentní automatizaci.

---

## 1. Repository Directory Structure Design

Návrh modulární adresářové struktury vycházející z GitOps a IaC best practices:

```
pve-node-iac/
├── README.md
├── LICENSE
├── .gitignore
├── .editorconfig
│
├── docs/
│   ├── architecture-decisions/
│   │   ├── ADR-001-ext4-over-zfs.md
│   │   ├── ADR-002-unprivileged-nesting.md
│   │   ├── ADR-003-named-volumes-over-bind-mounts.md
│   │   └── ADR-004-tailscale-subnet-routing.md
│   ├── diagrams/
│   │   └── topology-overview.mmd
│   └── runbooks/
│       ├── cold-start-recovery.md
│       └── backup-restore-procedure.md
│
├── host/
│   ├── sysctl/
│   │   ├── 10-memory-tuning.conf
│   │   ├── 20-network-forwarding.conf
│   │   └── 30-vm-dirty-ratio.conf
│   ├── grub/
│   │   └── grub.defaults
│   ├── modules/
│   │   └── blacklist.conf
│   ├── tailscale/
│   │   ├── tailscale-install.sh
│   │   └── subnet-router.env
│   ├── vzdump/
│   │   └── vzdump.conf
│   └── datacenter/
│       └── datacenter.cfg
│
├── lxc/
│   ├── templates/
│   │   ├── 100-docker-host.conf.tpl
│   │   └── 101-media-server.conf.tpl
│   ├── profiles/
│   │   ├── nesting-docker.profile
│   │   └── media-igpu.profile
│   └── hooks/
│       └── post-start-igpu-passthrough.sh
│
├── docker/
│   ├── compose.yaml
│   ├── compose.override.dev.yaml
│   ├── .env.example
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   │       ├── odoo.conf
│   │       └── upstream.conf
│   ├── init-scripts/
│   │   ├── 01-init.sql
│   │   └── 02-odoo-db-permissions.sql
│   ├── odoo/
│   │   ├── odoo.conf
│   │   └── addons/
│   │       └── .gitkeep
│   └── whisper/
│       └── models.env
│
├── scripts/
│   ├── lib/
│   │   ├── common.sh
│   │   └── validation.sh
│   ├── host-tuning.sh
│   ├── provision-containers.sh
│   ├── deploy-app-stack.sh
│   ├── verify-health.sh
│   └── backup-fleecing-setup.sh
│
├── systemd/
│   ├── tailscale-subnet-router.service
│   └── docker-stack-deploy.service
│
└── tests/
    ├── bats/
    │   ├── host-tuning.bats
    │   └── container-provision.bats
    └── compose-lint.sh
```

**Klíčové designové rozhodnutí:** Adresář `scripts/lib/` obsahuje sdílené funkce (logování, validace exit kódů, idempotency checks), které jsou sourcovány všemi skripty přes `source "$(dirname "$0")/lib/common.sh"`. Tím je zajištěna DRY principa napříč celou IaC vrstvou.

---

## 2. Sub-Agent Instruction Prompts (Task Chaining)

Následují tři nezávislé, plně specifikované prompty pro sub-agenty. Každý prompt je navržen tak, aby generoval idempotentní skript s explicitními validacemi.

---

### Prompt A: Generování `./scripts/host-tuning.sh`

```markdown
# ÚKOL: Vytvoření idempotentního skriptu `host-tuning.sh`

## Kontext
Skript běží na bare-metal Proxmox VE 9.x hostiteli (Debian-based).
Cílem je aplikovat kernel tuning, GRUB úpravy a nasadit Tailscale s subnet routingem.

## Vstupní proměnné (env)
- `TAILSCALE_AUTH_KEY` — Auth key pro Tailscale (povinný, exit 1 pokud chybí)
- `SUBNET_CIDR` — CIDR subnetu pro advertise-routes (default: `192.168.1.0/24`)
- `SWAPPINESS` — hodnota vm.swappiness (default: `10`)
- `DIRTY_RATIO` — hodnota vm.dirty_ratio (default: `10`)
- `DIRTY_BACKGROUND_RATIO` — hodnota vm.dirty_background_ratio (default: `5`)

## Požadované operace (v pořadí)

### Fáze 1: Sysctl tuning
1. Zápis do `/etc/sysctl.d/10-memory-tuning.conf`:
   - `vm.swappiness=${SWAPPINESS}`
   - `vm.dirty_ratio=${DIRTY_RATIO}`
   - `vm.dirty_background_ratio=${DIRTY_BACKGROUND_RATIO}`
   - `vm.vfs_cache_pressure=50`
   - `vm.overcommit_ratio=95`
2. Aplikace přes `sysctl --system` s zachycením stderr.
3. Validace: `sysctl -n vm.swappiness` musí vrátit nastavenou hodnotu. Pokud ne, exit 2.

### Fáze 2: GRUB úpravy
1. Záloha `/etc/default/grub` do `/etc/default/grub.bak.$(date +%s)`.
2. Úprava `GRUB_CMDLINE_LINUX_DEFAULT` — přidání `intel_iommu=on i915.enable_guc=3` pro iGPU passthrough do LXC 101.
3. Spuštění `update-grub` — exit kód 3 při selhání.
4. Validace: `grep -q "intel_iommu=on" /etc/default/grub` — exit 4 při neúspěchu.

### Fáze 3: Tailscale instalace a subnet routing
1. Kontrola existence binárky `tailscale`. Pokud neexistuje:
   - `curl -fsSL https://tailscale.com/install.sh | sh` — exit 5 při selhání.
2. Spuštění: `tailscale up --authkey="${TAILSCALE_AUTH_KEY}" --advertise-routes="${SUBNET_CIDR}" --accept-routes`
3. Povolení IP forwardingu:
   - Zápis `net.ipv4.ip_forward=1` a `net.ipv6.conf.all.forwarding=1` do `/etc/sysctl.d/20-network-forwarding.conf`.
   - `sysctl -p /etc/sysctl.d/20-network-forwarding.conf`.
4. Validace: `tailscale status` musí vypsat `Running`. Exit 6 při neúspěchu.
5. Validace: `cat /proc/sys/net/ipv4/ip_forward` musí vypsat `1`. Exit 7 při neúspěchu.

### Fáze 4: VZDump konfigurace
1. Zápis do `/etc/vzdump.conf`:
   ```
   bwlimit: 30000
   compress: zstd
   zstd: 3
   ```
2. Zápis do `/etc/pve/datacenter.cfg`:
   ```
   backup: fleecing=storage=local-lvm
   ```
3. Validace: `pveversion` musí být dostupný. Exit 8 při neúspěchu.

## Obecné požadavky
- Skript musí začínat `#!/usr/bin/env bash` a `set -euo pipefail`.
- Na začátku musí být kontrola: `[[ $EUID -eq 0 ]] || { echo "Vyžadováno root"; exit 99; }`.
- Každá fáze musí vypsat `[OK]` nebo `[FAIL]` s popisem.
- Skript musí být plně idempotentní — opětovné spuštění nesmí způsobit duplicitní konfiguraci (použij `grep -qF` před zápisem).
- Na konci vypiš souhrn všech aplikovaných změn.

## Výstup
Vygeneruj kompletní obsah souboru `./scripts/host-tuning.sh`.
```

---

### Prompt B: Generování `./scripts/provision-containers.sh`

```markdown
# ÚKOL: Vytvoření idempotentního skriptu `provision-containers.sh`

## Kontext
Skript běží na Proxmox VE 9.x hostiteli. Vytváří a konfiguruje dva LXC kontejnery
pomocí PVE CLI nástrojů (`pct`, `pvesh`). Kontejnery jsou založeny na Debian 12
LXC šabloně stažené z Proxmox repository.

## Vstupní proměnné (env)
- `CT_TEMPLATE` — název šablony (default: `debian-12-standard_12.7-1_amd64.tar.zst`)
- `STORAGE_POOL` — storage pro rootfs (default: `local-lvm`)
- `DOCKER_CTID` — CTID pro Docker host kontejner (default: `100`)
- `MEDIA_CTID` — CTID pro Media server kontejner (default: `101`)
- `DOCKER_RAM` — RAM limit pro LXC 100 v MB (default: `10240`)
- `MEDIA_RAM` — RAM limit pro LXC 101 v MB (default: `2048`)
- `DOCKER_CORES` — CPU jádra pro LXC 100 (default: `4`)
- `MEDIA_CORES` — CPU jádra pro LXC 101 (default: `2`)

## Požadované operace

### Fáze 1: Stažení LXC šablony (pokud neexistuje)
1. Kontrola: `pveam list local | grep -q "${CT_TEMPLATE}"`.
2. Pokud chybí: `pveam download local "${CT_TEMPLATE}"` — exit 10 při selhání.
3. Validace: opakovaný `pveam list local | grep -q "${CT_TEMPLATE}"` — exit 11.

### Fáze 2: Vytvoření LXC 100 (Docker Nesting Host)
1. Kontrola existence: `pct status "${DOCKER_CTID}" 2>/dev/null`. Pokud existuje, přeskoč vytváření (idempotence).
2. Pokud neexistuje, vytvoř:
   ```bash
   pct create "${DOCKER_CTID}" "local:vztmpl/${CT_TEMPLATE}" \
     --arch amd64 \
     --hostname docker-nest \
     --cores "${DOCKER_CORES}" \
     --memory "${DOCKER_RAM}" \
     --swap 0 \
     --rootfs "${STORAGE_POOL}:32" \
     --net0 name=eth0,bridge=vmbr0,ip=dhcp \
     --unprivileged 1 \
     --features nesting=1,keyctl=1 \
     --onboot 1
   ```
   Exit 12 při selhání `pct create`.
3. Validace existence: `pct config "${DOCKER_CTID}"` — exit 13 při neúspěchu.
4. Validace features: `pct config "${DOCKER_CTID}" | grep -q "nesting=1,keyctl=1"` — exit 14.
5. Validace unprivileged: `pct config "${DOCKER_CTID}" | grep -q "^unprivileged: 1"` — exit 15.

### Fáze 3: Vytvoření LXC 101 (Media Server)
1. Stejná idempotence jako Fáze 2.
2. Vytvoření:
   ```bash
   pct create "${MEDIA_CTID}" "local:vztmpl/${CT_TEMPLATE}" \
     --arch amd64 \
     --hostname media-server \
     --cores "${MEDIA_CORES}" \
     --memory "${MEDIA_RAM}" \
     --swap 0 \
     --rootfs "${STORAGE_POOL}:16" \
     --net0 name=eth0,bridge=vmbr0,ip=dhcp \
     --unprivileged 1 \
     --features nesting=1 \
     --onboot 1
   ```
3. Post-start injekce iGPU passthrough konfigurace:
   - Zápis do `/etc/pve/lxc/${MEDIA_CTID}.conf`:
     ```
     lxc.cgroup2.devices.allow: c 226:0 rwm
     lxc.cgroup2.devices.allow: c 226:128 rwm
     lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
     ```
4. Validace: `pct config "${MEDIA_CTID}" | grep -q "dev/dri"` — exit 16 při neúspěchu.

### Fáze 4: Spuštění kontejnerů
1. `pct start "${DOCKER_CTID}"` — exit 17 při selhání.
2. `pct start "${MEDIA_CTID}"` — exit 18 při selhání.
3. Validace běhu: `pct status "${DOCKER_CTID}" | grep -q "running"` — exit 19.
4. Validace běhu: `pct status "${MEDIA_CTID}" | grep -q "running"` — exit 20.

## Obecné požadavky
- `#!/usr/bin/env bash`, `set -euo pipefail`.
- Root kontrola: `[[ $EUID -eq 0 ]] || exit 99`.
- Source sdílených funkcí: `source "$(dirname "$0")/lib/common.sh"`.
- Logování každého kroku s `[OK]`/`[FAIL]` prefixem.
- Idempotence: skript musí být bezpečně re-spustitelný bez vedlejších efektů.
- Na konci vypiš tabulku: CTID | Hostname | Status | RAM | Cores.

## Výstup
Vygeneruj kompletní obsah souboru `./scripts/provision-containers.sh`.
```

---

### Prompt C: Generování auxiliárních konfiguračních souborů

```markdown
# ÚKOL: Vytvoření `nginx.conf` a `01-init.sql`

## Kontext
Tyto soubory jsou volume-mountovány do Docker Compose stacku běžícího uvnitř
LXC 100. Nginx funguje jako jediný ingress bod (port 80) a směruje provoz na
interní kontejnerové porty. PostgreSQL init skript zajišťuje inicializaci
pgvector rozšíření před startem Odoo.

---

## Soubor 1: `./docker/nginx/nginx.conf`

### Požadavky
1. Nginx běží v kontejneru `nginx:alpine`, naslouchá na portu 80.
2. Reverse proxy pro Odoo — upstream `web:8069` (Odoo longpolling na `web:8072`).
3. Reverse proxy pro n8n — upstream `automation-pipeline:5678` pod cestou `/n8n/`.
4. Reverse proxy pro Faster-Whisper API — upstream `whisper-api:8000` pod cestou `/whisper/`.
5. Zákaz přímého přístupu na databázový port (Zero Exposure Topology).
6. WebSocket podpora pro n8n (header `Upgrade`, `Connection`).
7. Timeoute: `proxy_read_timeout 600s` (Odoo dlouhé requesty při instalaci modulů).
8. Bezpečnostní hlavičky: `X-Frame-Options SAMEORIGIN`, `X-Content-Type-Options nosniff`.
9. Gzip komprese pro textové assety.
10. Access log do `/var/log/nginx/access.log`, error log `warn` úroveň.

### Struktura
```
events {}
http {
    upstream odoo { server web:8069; }
    upstream odoo_chat { server web:8072; }
    upstream n8n { server automation-pipeline:5678; }
    upstream whisper { server whisper-api:8000; }

    server {
        listen 80;
        # ... location bloky
    }
}
```

### Validace (zahrň do komentáře na konci souboru)
- `nginx -t` musí projít bez chyby.
- `curl -I http://localhost/` musí vracet HTTP 502 pokud Odoo neběží (správné chování proxy).
- `curl -I http://localhost/n8n/` musí vracet HTTP 200 nebo 302 když n8n běží.

---

## Soubor 2: `./docker/init-scripts/01-init.sql`

### Požadavky
1. Skript se spouští automaticky Docker entrypointem při první inicializaci
   databáze (je umístěn v `/docker-entrypoint-initdb.d/`).
2. Vytvoření databáze `odoo` (pokud neexistuje) — použij `SELECT 'CREATE DATABASE odoo' WHERE NOT EXISTS (...) \gexec`.
3. Vytvoření uživatele `odoo` s heslem z proměnné (nelze použít env přímo v SQL,
   proto skript předpokládá, že POSTGRES_USER=odoo je již nastaven v Compose).
4. Aktivace rozšíření `pgvector`:
   ```sql
   CREATE EXTENSION IF NOT EXISTS vector;
   ```
5. Nastavení oprávnění: uživatel `odoo` musí být vlastníkem databáze `odoo`
   a mít právo na `vector` extension.
6. Vytvoření druhé databáze `n8n` pro automation pipeline metadata.
7. Grant `ALL PRIVILEGES ON DATABASE n8n TO odoo`.
8. Skript musí být idempotentní — používat `IF NOT EXISTS` klauzule.

### Struktura
```sql
-- 01-init.sql: Inicializace pgvector a databázových schémat
-- Spouští se automaticky Docker entrypointem při first-run.
BEGIN;
-- ... SQL statements
COMMIT;
```

### Validace (zahrň do komentáře na konci souboru)
- Po inicializaci: `psql -U odoo -d odoo -c "SELECT extname FROM pg_extension;"` musí vypsat `vector`.
- `psql -U odoo -l` musí vypsat databáze `odoo` i `n8n`.

## Výstup
Vygeneruj kompletní obsah obou souborů s plnou syntaxí a komentáři v češtině.
```

---

## 3. Initial Architectural Review & Edge Cases

Následuje hloubková analýza kritických edge case scénářů, které mohou způsobit selhání při cold-startu nebo provozu.

### 3.1 Cold-Start Dependency Chain — Kritický problém

**Problém:** Docker Compose `depends_on` garantuje pouze pořadí startu kontejnerů, nikoliv jejich připravenost. Při cold-startu (např. po výpadku napájení nebo restartu hostitele) nastává následující race condition:

```
Timeline (cold-start):
T+0s   PostgreSQL container startuje
T+0s   Odoo container startuje (depends_on: db — splněno, ale DB ještě neakceptuje spojení)
T+2s   PostgreSQL: init locale-gen + entrypoint script
T+5s   PostgreSQL: BEGIN execution of 01-init.sql (CREATE EXTENSION vector)
T+6s   Odoo: pokus o připojení k DB → Connection refused nebo schema incomplete
T+7s   Odoo: crash / restart loop
T+8s   PostgreSQL: ready to accept connections
T+12s  Nginx: pokus o proxy na web:8069 → 502 Bad Gateway
```

**Důsledek:** Odoo se pokusí inicializovat své schéma dříve, než je `pgvector` rozšíření aktivováno. Pokud Odoo modul vyžaduje vector sloupce, dojde k `ERROR: type "vector" does not exist` a Odoo container se zacyklí v restart loop.

### 3.2 Řešení: Healthcheck Mechanics

Do `compose.yaml` je nutné implementovat následující healthcheck architekturu:

#### PostgreSQL Healthcheck (Gate Keeper)

```yaml
services:
  db:
    # ... existující konfigurace ...
    healthcheck:
      test: >
        pg_isready -U odoo -d odoo &&
        psql -U odoo -d odoo -tAc "SELECT 1 FROM pg_extension WHERE extname='vector'" | grep -q 1
      interval: 5s
      timeout: 5s
      retries: 20
      start_period: 30s
```

**Klíčový detail:** Healthcheck netestuje pouze `pg_isready` (což by prošlo dříve, než se spustí `01-init.sql`), ale explicitně ověřuje existenci `vector` extension. Teprve když tento test projde, je databáze považována za `healthy`.

#### Odoo Healthcheck (Conditional Start)

```yaml
  web:
    # ... existující konfigurace ...
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/login"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
```

**Poznámka:** `condition: service_healthy` nahrazuje jednoduché `depends_on` a garantuje, že Odoo nenastartuje dříve, než PostgreSQL projde healthcheckem (včetně ověření pgvector).

#### n8n Healthcheck

```yaml
  automation-pipeline:
    # ... existující konfigurace ...
    depends_on:
      db:
        condition: service_healthy
      whisper-api:
        condition: service_started
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
```

#### Nginx Reverse Proxy (Last to Start)

```yaml
  proxy:
    # ... existující konfigurace ...
    depends_on:
      web:
        condition: service_healthy
      automation-pipeline:
        condition: service_started
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:80/"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 10s
```

### 3.3 Další identifikované edge cases

| Edge Case | Riziko | Mitigace |
| :-- | :-- | :-- |
| **Whisper model download při cold-startu** | První start `faster-whisper-server` stahuje model `small` (~480MB). Pokud n8n pošle request dříve, dojde k timeoutu. | `start_period: 120s` na whisper-api healthchecku. N8n `depends_on: whisper-api: condition: service_healthy`. |
| **PostgreSQL locale-gen race** | Entrypoint volá `locale-gen` pro `cs_CZ.UTF-8`. Pokud balíček `locales` chybí v base image, selže ticho a DB nastartuje s `C` locale. Odoo pak může mít problémy s českou diakritikou v full-text search. | Přidat `apt-get install -y locales` do entrypointu před `locale-gen`, nebo použít custom Dockerfile s pre-baked locale. |
| **LXC cgroupsv2 memory ceiling** | Proxmox VE 9.x používá cgroupsv2. `mem_limit` v Docker Compose je respektován, ale LXC nadřazený kontejner má `memory: 10240` (10GB). Pokud Docker kontejnery souhrnně přesáhnou 10GB, OOM killer zabije proces uvnitř LXC, nikoliv Docker kontejner. | Součet `mem_limit` hodnot v Compose: 4g + 3g + 1g + 1g + 512m = 9.5GB. Rezerva 512MB pro Docker daemon + overhead. Toto je těsné — doporučuji snížit Odoo `mem_limit` na `2.5g` pro bezpečnostní margin. |
| **VZDump fleecing na LVM-Thin** | Backup fleecing vyžaduje dostatek volného místa v `local-lvm` thin pool. Při 480GB SSD s 4 VMs (~250GB thin provisioned) a 2 LXCs (~48GB) může fleecing vyčerpat thin pool a způsobit I/O freeze. | Monitorovat `lvs -o data_percent,pool_lv` a nastavit `thin_pool_autoextend_threshold` na 80% s autoextend. |
| **Tailscale subnet routing po rebootu** | `tailscale up --advertise-routes` není persistentní napříč rebooty bez systemd služby. Po výpadku napájení zůstanou VMs nedostupné. | Vytvořit `systemd` override: `systemctl edit tailscaled` s `Restart=always` a zajistit, že auth key je uložen v `/etc/systemd/system/tailscaled.service.d/auth.conf` jako `Environment=TAILSCALE_AUTH_KEY=...`. |
| **Docker Named Volume permission mapping** | PostgreSQL v Dockeru běží jako UID 999. V unprivileged LXC kontejneru je UID mapping posunutý. Docker daemon uvnitř LXC by měl toto řešit nativně, ale pokud LXC používá `idmap` s non-default mapping, mohou Named Volumes získat špatné oprávnění. | Validovat po prvním startu: `docker exec odoo_postgres id` a `docker exec odoo_postgres ls -la /var/lib/postgresql/data`. Pokud UID != 999, přidat `user: "999:999"` do Compose pro db service. |
| **iGPU passthrough do LXC 101 po rebootu** | `/dev/dri/renderD128` může mít po rebootu jiný minor číslo, pokud se změní pořadí inicializace jader. Statický `c 226:128` v `lxc.cgroup2` může být neplatný. | Přidat udev pravidlo na hostiteli: `/etc/udev/rules.d/99-intel-gpu.rules` s `SUBSYSTEM=="drm", KERNEL=="renderD128", SYMLINK+="intel_renderD"`. V LXC config pak mountovat přes symlink. |

### 3.4 Doporučený cold-start recovery postup

Pro runbook dokumentaci doporučuji následující sekvenci pro obnovu po tvrdém resetu:

1. **Host boot** → Proxmox auto-start LXC 100 a 101 (`onboot: 1`)
2. **LXC 100 start** → Docker daemon auto-start (pokud je `systemctl enable docker`)
3. **Docker Compose** → nasazen přes systemd službu `docker-stack-deploy.service` s `ExecStart=/usr/bin/docker compose -f /opt/pve-node-iac/docker/compose.yaml up -d`
4. **Healthcheck cascade** → PostgreSQL (30s) → Odoo (60s) → n8n (30s) → Nginx (10s)
5. **Total cold-start ETA:** ~2-4 minuty do plné dostupnosti

---

Tento architektonický plán pokrývá všechny vrstvy od bare-metal tuning přes kontejnerovou orchestraci až po cold-start resilience. Jakmile schválíte tuto strukturu, mohu přejít k generování samotných skriptů nebo k dalšímu zpřesnění kterékoliv sekce.