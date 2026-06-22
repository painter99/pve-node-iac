# Hardware

> Physical node and component constraints for the MVP deployment.

## Node profile

* **Chassis:** Dell Optiplex 3060 (Micro or SFF)
* **CPU:** Intel Core i5-9500T
  - 6 cores / 6 threads
  - 35 W TDP
  - 9th Gen Coffee Lake
* **iGPU:** Intel UHD Graphics 630 (Intel QuickSync enabled)
* **RAM:** 32 GB DDR4 Non-ECC
* **Storage:** 1x 480 GB SATA/NVMe SSD
* **File system:** `ext4` on top of Proxmox LVM-Thin

## Why LVM-Thin over ZFS

On a single-node, 32 GB RAM consumer setup, ZFS ARC overhead and write amplification on a single SSD would degrade performance and lifespan. LVM-Thin provides enough snapshot capability for VZDump while keeping the memory footprint small.

## Technology stack

See [stack_badges](../stack_badges.md) for a complete badge catalog.

## Related documentation

* Allocation matrix: [RESOURCE-BUDGET](RESOURCE-BUDGET.md)
* Host tuning: [HOST-TUNING](HOST-TUNING.md)
