locals {
  talos_nodes = {
    "cp-3" = {
      vm_id = 130
      name  = "talos-cp-3"
      ip    = "10.10.10.32"
      mac   = "BC:24:11:C5:51:79"
    }
  }
}

module "talos_vms" {
  source = "../../modules/proxmox-talos-vm"
  for_each = local.talos_nodes

  node_name       = var.proxmox_node
  vm_id           = each.value.vm_id
  vm_name         = each.value.name
  talos_version   = var.talos_version
  talos_schematic = var.talos_schematic_id
  datastore       = var.datastore
  iso_datastore   = var.iso_datastore
  bridge_name     = var.bridge_name
  vlan_id         = var.vlan_id
}