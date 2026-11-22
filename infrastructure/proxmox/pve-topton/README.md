# PVE1 — Proxmox Infrastructure as Code

Managed by Terraform/OpenTofu with the `bpg/proxmox` provider.

## Host

| Item | Value |
|---|---|
| Hostname | `pve1` |
| Proxmox IP | `192.168.2.11:8006` (transitional; will move to `10.10.10.20` on VLAN 10) |
| Datastore | `local-lvm` |
| ISO store | `local` (`/var/lib/vz/template/iso/`) |

## NIC Layout (unusual naming — documented for portability)

| Interface | Role | Bridge |
|---|---|---|
| `nic0` | WAN uplink to Fiber ONT | `vmbr0` (pre-existing, not TF-managed) |
| `nic1` | Room run — Living Room | `vmbr1` |
| `nic2` | Room run — Bedroom 1 | `vmbr1` |
| `nic3` | Room run — Bedroom 2 | `vmbr1` |
| `nic4` | 10G SFP+ → Horaco core switch | `vmbr1` |
| `nic5` | 10G SFP+ (spare) | `vmbr1` |

> **Warning:** NIC names are `nic0`–`nic5`, not the usual `eno1`/`enp1s0`. If PVE1 is ever reinstalled, verify names match before `terraform apply`.

## VMs

| VM ID | Name | Role | VLAN | IP |
|---|---|---|---|---|
| 100 | `opnsense` | Router/firewall | trunk (all) | `.1` on each VLAN |
| 110 | `talos-cp-1` | Kubernetes control plane | 10 | `10.10.10.30` |

## Bridge Layout

- **`vmbr0`** — pre-existing, bridged to `nic0`. Carries management. **Not managed by Terraform.**
- **`vmbr1`** — Terraform-managed, VLAN-aware (10/20/30/40/50), trunk to all house runs + office.

## Manual Prerequisites

1. **OPNsense ISO** must be uploaded to `local` storage before `tofu apply`:
   - Download from https://opnsense.org/download/ (`dvd`/`amd64`)
   - Decompress `.iso.bz2`
   - Upload via PVE UI → `local` → ISO Images → Upload
   - Filename must match `file_id` in `opnsense.tf`

2. **API token** in `terraform.tfvars` (see `variables.tf` for format).

3. **Proxmox role/token** must have `SDN.Audit` + `SDN.Use` (see `bpg/proxmox` docs).