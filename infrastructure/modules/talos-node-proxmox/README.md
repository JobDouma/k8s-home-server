# proxmox-talos-vm

Creates a single Talos Linux VM on Proxmox VE, with its boot ISO
downloaded from the Talos Image Factory. Designed to be called from
a root module with `for_each` over a map of nodes.

## Usage

module "talos_vms" {
  source   = "../../modules/proxmox-talos-vm"
  for_each = local.talos_nodes

  node_name       = var.proxmox_node
  vm_id           = each.value.vm_id
  vm_name         = each.value.name
  mac_address     = each.value.mac
  talos_version   = var.talos_version
  talos_schematic = var.talos_schematic_id
  datastore       = var.datastore
  iso_datastore   = var.iso_datastore
  bridge_name     = "vmbr1"
  vlan_id         = 10
}

## Inputs

| Name            | Type   | Required | Description                                              |
|-----------------|--------|----------|----------------------------------------------------------|
| node_name       | string | yes      | Proxmox node hostname (e.g. "pve1")                      |
| vm_id           | number | yes      | Proxmox VM ID                                            |
| vm_name         | string | yes      | VM display name                                          |
| mac_address     | string | no       | Static NIC MAC. Should match OPNsense DHCP reservation.  |
| talos_version   | string | yes      | Talos version, e.g. "v1.14.2"                            |
| talos_schematic | string | yes      | Image Factory schematic ID                               |
| datastore       | string | yes      | Storage for VM disks (e.g. "local-lvm")                  |
| iso_datastore   | string | yes      | Storage for ISOs (e.g. "local")                          |
| bridge_name     | string | yes      | Proxmox bridge name (e.g. "vmbr1")                       |
| vlan_id         | number | yes      | VLAN tag applied to the NIC                              |

## Outputs

| Name  | Description                                                  |
|-------|--------------------------------------------------------------|
| vm_id | The Proxmox VM ID (collected by the root module into a map)  |
| vm_ip | Placeholder only — real IP is enforced by OPNsense DHCP      |

## Notes

- One module invocation = one VM. The caller owns the `for_each` loop.
- `mac_address` is set on the NIC so OPNsense DHCP reservations
  cannot drift if a VM is destroyed and recreated.
- `started = false` and `ignore_changes = [started]` are intentional:
  Talos VMs are started manually so the first boot happens only after
  OPNsense is routing the management VLAN.
- The Talos ISO is downloaded per module invocation. That is fine for
  one Talos VM per host (the current setup). If you ever run two
  Talos VMs on the same Proxmox node, hoist the download resource out
  of this module into the root module to avoid a file_name conflict.
