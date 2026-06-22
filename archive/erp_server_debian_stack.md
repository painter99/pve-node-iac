Kompletní původní realizační plán a skripty, které celou tuto architekturu nasadí na ThinkPad X230, jako PoC, na jeden zátah.
------------------------------
## Krok 1: Inicializační skript pro Host OS (Debian 13)
Tento skript spustí na hostiteli konfiguraci sítě, aktualizuje GRUB (včetně vypnutí mitigací a aktivace intel_pstate), alokuje Hugepages a nainstaluje minimalistické KVM.
Vytvořte soubor setup-host.sh:

#!/bin/bashset -e

echo "=== 1. Aktualizace systému ==="
sudo apt update && sudo apt upgrade -y

echo "=== 2. Instalace minimalistického KVM (bez doporučeného balastu) ==="
sudo apt install --no-install-recommends -y qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients virtinst bridge-utils sysfsutils

sudo adduser $USER libvirt
sudo adduser $USER kvm

echo "=== 3. Konfigurace GRUB (Optimalizace Ivy Bridge) ==="# Záloha původního GRUBu
sudo cp /etc/default/grub /etc/default/grub.bak# Nastavení optimalizovaného řádku
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt mitigations=off intel_pstate=active"/' /etc/default/grub
sudo update-grub

echo "=== 4. Konfigurace Sysctl (Hugepages + I/O) ==="
sudo tee /etc/sysctl.d/99-kvm-tuning.conf <<EOF
# Alokace 10 GB v Hugepages (5120 * 2MB)
vm.nr_hugepages = 5120
# Ochrana SATA SSD před zahlcením
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.swappiness = 10
EOF
sudo sysctl --system

echo "=== 5. Konfigurace Network Bridge ==="# POZNÁMKA: Ověřte si název rozhraní (např. enp3s0) přes 'ip a' a upravte podle potřeby
sudo tee /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

iface enp3s0 inet manual

auto br0
iface br0 inet dhcp
    bridge_ports enp3s0
    bridge_stp off
    bridge_fd 0
EOF

echo "=== HOTOVO! Restartujte ThinkPad, aby se aplikoval GRUB a Hugepages ==="

Spusťte pomocí: chmod +x setup-host.sh && sudo ./setup-host.sh
------------------------------
## Krok 2: Instalace a spuštění Ubuntu VM (KVM)
Po restartu hostitele spusťte tento upřesněný příkaz pro vytvoření VM. Obsahuje přesně validované parametry: Hugepages, PCID flag, io_uring, iothread a Multiqueue síť.

virt-install \
  --name=ubuntu-docker-crm \
  --vcpus=2,cores=2,threads=1 \
  --memory=10240 \
  --memorybacking hugepages=yes \
  --cpu host-passthrough,+pcid \
  --machine=q35 \
  --network bridge=br0,model=virtio,driver.queues=2 \
  --controller type=scsi,model=virtio-scsi \
  --disk path=/var/lib/libvirt/images/ubuntu.qcow2,size=50,bus=scsi,cache=none,io=io_uring,discard=unmap,iothread=1 \
  --os-variant=ubuntu24.04 \
  --graphics none \
  --console pty,target_type=serial \
  --location http://ubuntu.com \
  --extra-args "console=ttyS0,115200n8"

------------------------------
## Krok 3: Konfigurace Guest OS (Uvnitř Ubuntu VM)
Jakmile dokončíte textovou instalaci Ubuntu a přihlásíte se do VM přes SSH, spusťte uvnitř VM tyto příkazy pro vyladění diskového plánovače na none, zapnutí oříznutí SSD (fstrim) a nastavení dirty stránek:

# 1. Nastavení sysctl pro VM
sudo tee /etc/sysctl.d/99-vm-tuning.conf <<EOF
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF
sudo sysctl --system
# 2. Nastavení plánovače disku na 'none' přes udev rule
sudo tee /etc/udev/rules.d/60-scheduler.rules <<EOF
ACTION=="add|change", KERNEL=="sd[a-z]|sda[0-9]*", ATTR{queue/scheduler}="none"
EOF
sudo udevadm trigger
# 3. Aktivace pravidelného fstrim
sudo systemctl enable --now fstrim.timer

------------------------------
## Krok 4: Finální compose.yaml (S CPU limity a přípravou pro AI)
Architekt doporučil hotový image s pgvector, ale musíme zajistit českou lokalizaci. Oficiální image pgvector/pgvector:16 je postaven na Debianu, takže v něm stačí vygenerovat české lokály přímo při startu kontejneru.
Zde je finální compose.yaml s implementovaným CPU limitem (cpus: "1.5") u Odoo, aby databáze měla vždy garantovaný procesorový čas.

services:
  db:
    image: pgvector/pgvector:16
    container_name: odoo19_db
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=vase_top_heslo
      - LANG=cs_CZ.UTF-8
      - LC_ALL=cs_CZ.UTF-8
    volumes:
      - odoo-db-data:/var/lib/postgresql/data
    # Příkaz vygeneruje českou lokalizaci v image před spuštěním Postgresu
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
      "    restart: always
    mem_limit: 4g

  web:
    image: odoo:19.0
    container_name: odoo19_web
    depends_on:
      - db
    ports:
      - "8069:8069"
    environment:
      - HOST=db
      - USER=odoo
      - PASSWORD=vase_top_heslo
    volumes:
      - odoo-web-data:/var/lib/odoo
    restart: always
    mem_limit: 4g
    # Architektem doporučený CPU limit pro ochranu databáze před uvařením CPU
    cpus: "1.5"
volumes:
  odoo-db-data:
  odoo-web-data:

## Krok 5: Aktivace pgvector v databázi (Day One)
Až celý stack spustíte pomocí docker compose up -d, přihlaste se do kontejneru s databází a zapněte vektorové vyhledávání:

docker exec -it odoo19_db psql -U odoo -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

Pokud příkaz vrátí CREATE EXTENSION, máte na svém ThinkPadu X230 připravenou plnohodnotnou AI-ready databázi s hardwarově akcelerovaným vyhledáváním (přes AVX z host-passthrough).

