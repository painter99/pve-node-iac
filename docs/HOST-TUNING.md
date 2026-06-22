# Host Tuning

> Mandatory Proxmox VE host-level tuning after a fresh install.

## 1. GRUB kernel parameters

Edit `/etc/default/grub`:

```properties
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt intel_pstate=active"
```

* `intel_iommu=on iommu=pt`: enables PCIe passthrough for the iGPU used in LXC 101.
* `intel_pstate=active`: modern Intel CPU frequency scaling.

Apply the change:

```bash
update-grub
```

A reboot is required before the new parameters take effect.

## 2. Sysctl I/O and memory tuning

Create `/etc/sysctl.d/99-pve-tuning.conf`:

```ini
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
```

* Low `dirty_ratio` limits write bursts and protects a consumer SSD from I/O wait.
* Low `swappiness` keeps pages in RAM.

Apply without reboot:

```bash
sysctl --system
```

## 3. LXC container profiles

### LXC 100: unprivileged Docker host

Path on Proxmox: `/etc/pve/lxc/100.conf`

```properties
unprivileged: 1
features: nesting=1,keyctl=1
onboot: 1
memory: 10240
swap: 0
cores: 2
```

### LXC 101: media server with iGPU passthrough

Path on Proxmox: `/etc/pve/lxc/101.conf`

```properties
unprivileged: 1
features: nesting=1
onboot: 1
memory: 2048
swap: 0
cores: 2
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

## 4. Automation

The tuning steps above are implemented idempotently in `scripts/setup-host.sh`.
