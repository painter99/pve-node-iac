# proxmox/network

> Tailscale subnet routing on the bare-metal Proxmox host.

## 🗺️ Visual Component Map

```mermaid
graph TD
    EXT["Remote Client"] -->|Encrypted WireGuard| TS["Tailscale Mesh"]
    TS -->|Subnet route 192.168.1.0/28 (default)| PVE["Proxmox VE Host"]

    PVE -->|Port 8006| PVE_GUI["Proxmox Web GUI"]
    PVE -->|Routes to| VM1["VM1 Pop!_OS"]
    PVE -->|Routes to| VM2["VM2 Zorin OS"]
    PVE -->|Routes to| VM3["VM3 Zorin OS"]
    PVE -->|Routes to| VM4["VM4 Windows"]
    PVE -->|Port 80| LXC100["LXC 100 Docker Host"]

    NET["tailscale-routes.sh"] -.->|Configures| TS
```

## 📄 Description and Context

`tailscale-routes.sh` installs Tailscale (if missing), enables IPv4/IPv6 forwarding and advertises the local subnet (`192.168.1.0/24` by default) so that family VMs and the LXC containers are reachable over the Tailscale mesh without public port exposure.

## 🔗 System Links

* **Parent context:** [proxmox/README](../README.md)
* **Interfaces:**
  * **Input:** runs on the bare-metal Proxmox host as root
  * **Output:** `tailscale up --advertise-routes=192.168.1.0/28`
* **Dependencies:**
  * `TAILSCALE_AUTH_KEY` environment variable
  * IPv4/IPv6 forwarding enabled by `../../scripts/setup-host.sh`
