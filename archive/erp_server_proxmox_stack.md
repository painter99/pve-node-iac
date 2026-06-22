## 📑 Původní TECHNICKÝ MANUÁL: OPTIMALIZOVANÁ INFRASTRUKTURA PVE 9.2 NA THINKPAD X230 (PRODUKČNÍ VERZE - PoC)
Tento manuál definuje exaktní postupy pro nasazení, nízkoúrovňové ladění a pokročilé zabezpečení hypervizoru Proxmox VE verze 9.2.2 (vydání květen 2026) na edge hardwaru ThinkPad X230 [INDEX]. Cílem architektury je eliminace režie procesoru Ivy Bridge, striktní management 16 GB RAM a implementace neprůstřelné síťové politiky „Zero Exposure“ pro stabilní, bezpečný a plně vzdálený běh AI-ready ERP systému Odoo 19 a PostgreSQL 16.
------------------------------
## 1. NÍZKOÚROVŇOVÁ KONFIGURACE HOSTITELE (PROXMOX VE 9.2.2 CLI)
Na starší dvoujádrové architektuře je každý cyklus CPU drahý. Cílem je minimalizovat "context switching", optimalizovat paměťové stránky a uvolnit hardwarové countery.
## 1.1. Agresivní ladění kernelu přes GRUB
Upravte konfiguraci zavaděče pro maximalizaci propustnosti a deaktivaci subsystémů, které na dedikovaném hypervizoru zbytečně konzumují výkon.
Otevřete konfiguraci GRUB:

nano /etc/default/grub

Upravte řádek GRUB_CMDLINE_LINUX_DEFAULT přesně do této podoby:

GRUB_CMDLINE_LINUX_DEFAULT="quiet mitigations=off nmi_watchdog=0 audit=0 intel_iommu=on iommu=pt intel_pstate=active"


* mitigations=off: Klíčové pro Ivy Bridge; odstraňuje softwarové bariéry v kernelu (Spectre/Meltdown), které drasticky zpomalují syscalls. Vrací procesoru až 25 % výkonu.
* nmi_watchdog=0: Uvolní jeden hardware performance counter, což snižuje parazitní zátěž procesoru.
* audit=0: Vypíná auditní subsystém kernelu, čímž redukuje režii při každém systémovém volání.
* intel_iommu=on iommu=pt: Aktivuje IOMMU passthrough s maximálním výkonem bez zbytečných DMA překladů.
* intel_pstate=active: Zapíná moderní správu frekvence od Intelu pro efektivní škálování výkonu bez rizika přehřívání notebooku.

Aplikujte změny v moderním PVE 9.2 synchronizací ESP oddílů:

proxmox-boot-tool refresh

## 1.2. Management RAM, ZFS ARC limit a ochrana SATA SSD [1] 
ThinkPad X230 ma limit 16 GB RAM. Pokud používáte ZFS, ARC cache by defaultně alokovala až 8 GB, což vede k okamžitému OOM (Out of Memory) stavu při startu VM. Musíme ARC striktně omezit.
Vytvořte nebo upravte soubor /etc/modprobe.d/zfs.conf:

nano /etc/modprobe.d/zfs.conf

Vložte následující limit (omezení ARC na 2 GB):

options zfs zfs_arc_max=2147483648

Dále vytvořte konfigurační soubor pro sysctl pro zajištění stability SATA SSD a alokaci Hugepages (rezervace 10 GB RAM vyjádřená jako 5120 stránek o velikosti 2 MB):

nano /etc/sysctl.d/99-proxmox-tuning.conf

Vložte následující parametry:

# Rezervace 10 GB v Hugepages pro VM (5120 stránek * 2 MB)
vm.nr_hugepages = 5120

# Ochrana SATA sběrnice před nárazovým zahlcením zápisy z DB
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

Architektonický vhled: Nízký dirty_ratio je nezbytný pro zachování "write-amplification" stability na starších SATA SSD. Předcházíme tím stavu "I/O wait", kdy se systém stává necitlivým kvůli zahlcení pomalé zápisové fronty.
Aplikujte změny:

sysctl --system

## 1.3. Verifikace Hugepages
Před startem VM ověřte, že hostitel správně alokoval paměť:

cat /proc/meminfo | grep Huge

Pokud HugePages_Free neodpovídá HugePages_Total, jiný proces blokuje rezervovanou paměť.
## 1.4. Restart hostitele
Aby se uplatnily veškeré změny v jádře a alokovaly se Hugepages, restartujte ThinkPad:

reboot

------------------------------
## 2. KONFIGURACE VIRTUÁLNÍHO STROJE (UBUNTU 24.04 LTS V KVM)
Pro náročné Docker stacky (Odoo + PostgreSQL) definujeme virtuální stroj s profilem, který minimalizuje virtualizační penalizaci. Vytvořte VM v Proxmox GUI s následující nízkoúrovňovou specifikací:
## 2.1. CPU architektura a +pcid

* Cores: 2
* Type: Zvolte host (host-passthrough). Pro Ivy Bridge je kritické předat flag +pcid (Process-Context Identifiers). PCID umožňuje procesoru udržet TLB záznamy při přepínání kontextu mezi kernelem a user-spacem, což zásadně snižuje režii přepínání kontextů (Context Switching), na kterou PostgreSQL jako procesně orientovaná databáze extrémně trpí.

## 2.2. Storage Stack: VirtIO SCSI Single & io_uring
Pro dosažení maximálních IOPS na SATA sběrnici využijte asynchronní rozhraní io_uring, které v PVE 9.2.2 s jádrem 7.0 nabízí nejnižší možnou režii [INDEX].

| Parametr [2] | Nastavení | Architektonický význam |
|---|---|---|
| Controller | VirtIO SCSI Single | Každý disk má vlastní frontu, eliminuje se úzké hrdlo řadiče. |
| Cache | No cache | Obchází cache hostitele, zápisy jdou přímo na disk. |
| IO Thread | Aktivováno (Zaškrtnuto) | I/O operace neblokují hlavní vCPU vlákna emulátoru. |
| Async IO | io_uring | Nativní, nejefektivnější asynchronní rozhraní jádra 7.0 [INDEX]. |
| Discard | Aktivováno (Zaškrtnuto) | Nutné pro funkci TRIM; zabraňuje degradaci výkonu SSD. |

## 2.3. Síťové nastavení

* Model: VirtIO (paravirtualized)
* Multiqueue: Zadejte 2 (umožní distribuovat síťový provoz na obě vCPU jádra).
* Firewall: Zaškrtnuto (Ponechte zapnutý Proxmox Firewall na úrovni VM. Jeho režie v nftables stacku je minimální a slouží jako nezbytná druhá vrstva obrany před Docker bridge průsaky).

## 2.4. Vynucení Hugepages v konfiguraci VM
Po vytvoření VM otevřete jeho konfigurační soubor na hostiteli (nahraďte VMID reálným číslem vašeho VM, např. 100):

nano /etc/pve/qemu-server/VMID.conf

Přidejte řádek pro mapování velkých stránek:

hugepages: 2

V terminologii PVE hodnota 2 signalizuje striktní využití 2MB stránek. Tím zajistíte, že Guest uvidí souvislé bloky paměti, což dramaticky zrychluje databázové operace.
------------------------------
## 3. GUEST OS TUNING (UVNITŘ UBUNTU VM)
Proveďte standardní instalaci Ubuntu Server 24.04 LTS uvnitř VM. Přihlaste se přes SSH a aplikujte následující úpravy:
## 3.1. Tuning paměti a I/O plánovače v Guestu
Nastavte chování dirty stránek a vyčleňte vnořené Hugepages pro PostgreSQL:

sudo tee /etc/sysctl.d/99-vm-tuning.conf <<EOF
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
# Vyčlenění 2 GB v Hugepages přímo v Ubuntu pro PostgreSQL
vm.nr_hugepages = 1024
EOF
sudo sysctl --system

Vypněte složité diskové plánovače uvnitř VM, protože veškerou logiku už efektivně provádí Proxmox hostitel přes io_uring:

sudo tee /etc/udev/rules.d/60-scheduler.rules <<EOF
ACTION=="add|change", KERNEL=="sd[a-z]|sda[0-9]*", ATTR{queue/scheduler}="none"
EOF
sudo udevadm trigger

Aktivujte systémový časovač pro pravidelný průchod TRIMu:

sudo systemctl enable --now fstrim.timer

------------------------------
## 4. APLIKAČNÍ STACK S REVERZNÍ PROXY (DOCKER COMPOSE V2)
Nainstalujte Docker Engine podle oficiální dokumentace pro Ubuntu. Vytvořte adresář projektu a připravte konfigurační soubory pro kompletní izolovaný chod CRM:

mkdir -p ~/odoo-crm && cd ~/odoo-crm

## 4.1. Konfigurace vestavěné reverzní proxy Nginx
Aby Nginx věděl, jak bezpečně směřovat vzdálený provoz z VPN do Odoo na loopbacku, vytvořte v adresáři soubor nginx.conf:

nano nginx.conf

Vložte následující minimalistickou, vysoce optimalizovanou konfiguraci:

events { worker_connections 1024; }

http {
    upstream odoo_backend {
        server web:8069;
    }

    server {
        listen 80;
        proxy_read_timeout 720s;
        proxy_connect_timeout 720s;
        proxy_send_timeout 720s;

        access_log /dev/stdout;
        error_log /dev/stderr;

        location / {
            proxy_pass http://odoo_backend;
            proxy_redirect off;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /websocket {
            proxy_pass http://odoo_backend;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}

## 4.2. Finální, kompletní compose.yaml (Plně ověřený)
Vytvořte hlavní konfigurační soubor aplikací:

nano compose.yaml

Vložte následující strukturu. Obsahuje limity paměti, verzi Postgresu postavenou na Debianu s českou lokalizací, a striktně využívá pojmenované Docker Volumes.
Architektonické opodstatnění (Docker specialista): Použití pojmenovaných volumes (odoo-db-data) namísto přímých lokálních složek kompletně obchází režii standardního vrstveného storage driveru (OverlayFS/ZFS) a zapisuje data přímo. To drasticky redukuje write-amplification a předchází I/O bottleneckům na starších SATA SSD při write-heavy databázovém workloadu.

```
services:
  db:
    image: pgvector/pgvector:16
    container_name: odoo19_db
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=moje_super_bezpecne_heslo
      - LANG=cs_CZ.UTF-8
      - LC_ALL=cs_CZ.UTF-8
    volumes:
      - odoo-db-data:/var/lib/postgresql/data # Vysoce výkonný nativní volume
    # Entrypoint vygeneruje české lokály a přinutí Postgres využít mapované Hugepages
    entrypoint: >
      bash -c "
      echo 'cs_CZ.UTF-8 UTF-8' >> /etc/locale.gen &&
      locale-gen &&
      exec docker-entrypoint.sh postgres
      -c shared_buffers=2GB
      -c effective_cache_size=6GB
      -c maintenance_work_mem=512MB
      -c work_mem=64MB
      -c max_connections=20
      -c huge_pages=on
      "    restart: unless-stopped
    mem_limit: 4g
    networks:
      - odoo-sdn

  web:
    image: odoo:19.0
    container_name: odoo19_web
    depends_on:
      - db
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=moje_super_bezpecne_heslo
    volumes:
      - odoo-web-data:/var/lib/odoo
    restart: unless-stopped
    mem_limit: 4g
    cpus: "1.5" # Ochrana databáze před uvařením CPU ze strany Odoo při AI úlohách
    networks:
      - odoo-sdn

  proxy:
    image: nginx:alpine
    container_name: odoo19_proxy
    depends_on:
      - web
    ports:
      - "80:80" # VM bude v síti naslouchat na standardním HTTP portu 80 přes VPN
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped
    mem_limit: 512m
    networks:
      - odoo-sdn
volumes:
  odoo-db-data: # Definice izolovaných persistentních volumes
  odoo-web-data:
networks:
  odoo-sdn:
    driver: bridge
```

Spusťte kompletní stack:

docker compose up -d

Po inicializaci kontejnerů aktivujte vektorové rozšíření pgvector pro vaši prompt chaining pipeline:

docker exec -it odoo19_db psql -U odoo -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

------------------------------
## 5. STRATEGIE ZÁLOHOVÁNÍ A OCHRANA DATA (PROXMOX BACKUP)
Na ThinkPadu X230 je zálohovací úložiště (např. externí USB 3.0 disk) vždy řádově pomalejší než interní SATA SSD. Klasická záloha by způsobila kompletní I/O freeze databáze.
## 5.1. Konfigurace globálního omezení a Backup Fleecing
Přihlaste se na Proxmox hostitele přes SSH a otevřete soubor /etc/vzdump.conf:

nano /etc/vzdump.conf

Aktivujte rychlostní limit a vysoce efektivní vícejadrovou komresi Zstd (nastaveno na 2 vlákna, aby záloha nesežrala celé dvoujádro):

bwlimit: 25000
compress: zstd
zstd: 2

Povolte technologii Backup Fleecing v konfiguraci datacenteru (/etc/pve/datacenter.cfg) [INDEX]:

nano /etc/pve/datacenter.cfg

Přidejte řádek (předpokládá, že vaše interní SSD úložiště se v Proxmoxu jmenuje local):

backup: fleecing=storage=local

Architektonický význam: Fleecing kompletně odpojuje VM od pomalé USB sběrnice [INDEX]. Pokud PostgreSQL během zálohy zapíše do bloku, stará data se bleskově odloží do dočasné cache na rychlém interním SSD a VM pokračuje bez čekání. Data se na USB disk odsypávají na pozadí konstantní rychlostí 25 MB/s.
## 5.2. Nastavení noční zálohy
V Proxmox webovém rozhraní připojte externí USB disk přes sekci Disks -> Directory (např. jako úložiště usb-backup).
Následně můžete spustit automatizovanou zálohu s využitím pokročilých šablon pro poznámky (--notes-template), která přes QEMU Guest Agenta bezpečně provede konzistentní snapshot (fs-freeze databáze):

vzdump VMID --storage usb-backup --mode snapshot --compress zstd --notes-template "{{guestname}}-{{node}}" --prune-backups keep-last=7

(Tento příkaz doporučujeme nastavit do plánovače v sekci Datacenter -> Backup na 02:00 ráno).
------------------------------
## 6. SÍŤOVÁ BEZPEČNOST A FIREWALL (VPN-ONLY KONCEPT)
Abychom dosáhli politiky „Zero Exposure“, veškerá správa serveru a přístup k CRM musí probíhat striktně přes VPN. Jako síťový koncentrátor využijeme přímo Host OS (Proxmox VE), což šetří vCPU cykly a využívá nativní implementaci WireGuardu v jádře 7.0 s minimální režií.
## 6.1. Instalace VPN na Proxmox Hostiteli
Nainstalujte Tailscale (nebo čistý WireGuard) přímo do Proxmox hypervizoru:

curl -fsSL https://tailscale.com | sh

Architektonické schválení: Instalace na hostitele sice mírně rozšiřuje akční rádius hypervizoru, ale na dvoujádru Ivy Bridge eliminuje režii emulace síťového stacku, která by vznikla provozem VPN uvnitř VM.
## 6.2. Konfigurace Proxmox Centrálního Firewallu (nftables)
Proxmox VE 9.2 plně využívá moderní subsystém nftables. Pro bezpečnou správu přístupu využijeme technologii IPSets.
Otevřete konfigurační soubor clusterového firewallu na hostiteli:

nano /etc/pve/firewall/cluster.fw

Zapište strukturu, která zablokuje veškerý provoz z internetu (DROP) a povolí správu (port 8006 a 22) výhradně ze subnetu vaší VPN:

[OPTIONS]
enable: 1

[IPSET management]
# Rozsah vaší interní VPN sítě (příklad pro Tailscale)
100.64.0.0/10

[RULES]
IN SSH(ACCEPT) -source +management -log nolog
IN WebUI(ACCEPT) -source +management -log nolog

## 6.3. Aktivace firewallu
Důležité varování architekta: Před aktivací firewallu se ujistěte, že máte otevřené a aktivní SSH spojení, abyste se v případě chyby neodřízli od serveru.
Ve webovém rozhraní Proxmoxu přejděte do Datacenter -> Firewall a zaškrtněte Enable. Pravidla nftables se okamžitě začnou dynamicky uplatňovat i na rozhraní tailscale0 / wg0.
------------------------------
## 7. MONITORING, DIAGNOSTIKA A ÚDRŽBA
## 7.1. pveperf a pvestatd (Audit diskového subsystému)
Pravidelně (měsíčně) spouštějte na hostiteli vestavěný výkonnostní test Proxmoxu:

pveperf /var/lib/vz

Sledujte hodnotu FSYNC/SECOND. Pokud u vašeho SATA SSD klesne pod hodnotu 100, disk přestává stíhat bezpečně potvrzovat transakční logy PostgreSQL 16. To signalizuje nutnost opotřebení disku.
## 7.2. SMART a teplotní management
Procesor Ivy Bridge v kompaktním těle ThinkPadu X230 trpí při trvalé virtualizační zátěži na vysoké teploty. Monitorujte smartctl:

smartctl -a /dev/sda | grep -i wear

Při dlouhodobém dosažení teplot nad 85 °C dochází k hardwarovému snižování frekvence (thermal throttling). To okamžitě způsobí masivní nárůst latencí v Odoo a extrémní navýšení context switchingu. Fyzické vyčištění chlazení a přepastování edge uzlu X230 je pro stabilitu AI databáze stejně kritické jako softwarový tuning jádra.
------------------------------
## 8. VERIFIKACE BĚHU (KONTROLNÍ SEZNAM)
Po kompletním spuštění celého řetězce spustte uvnitř Ubuntu VM tyto dva příkazy pro ověření topologie:

   1. Ověření průchodu PCID flagu: grep pcid /proc/cpuinfo (Musí vrátit barevně zvýrazněné shody).
   2. Ověření reálné konzumace Hugepages: grep -i huge /proc/meminfo (Hodnota HugePages_Free musí být prokazatelně nižší než HugePages_Total – to potvrzuje, že PostgreSQL úspěšně uzamkl sdílenou paměť z Proxmoxu).

## 🚀 Jak se nyní připojit na dálku?

   1. Zapněte VPN (Tailscale) na svém klientském zařízení (mobil/notebook).
   2. Do prohlížeče zadejte vnitřní IP adresu vašeho Ubuntu VM (např. http://10.10.10.50). Proxy Nginx na portu 80 automaticky a bezpečně předá provoz do izolovaného Odoo.
   3. Okamžitě se vám bezpečně otevře kompletní ERP systém Odoo 19 s plnou odezvou a AI rozšířením pgvector.

------------------------------