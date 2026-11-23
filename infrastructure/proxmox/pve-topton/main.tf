# infrastructure/proxmox/pve-topton/main.tf

locals {
  talos_nodes = {
    "cp-1" = {
      vm_id = 110
      name  = "talos-cp-1"
      ip    = "10.10.10.30"
      mac   = "BC:24:11:C5:51:77"
    }
  }
}

module "talos_vms" {
  source   = "../../modules/proxmox-talos-vm"
  for_each = local.talos_nodes

  node_name       = var.proxmox_node
  vm_id           = each.value.vm_id
  vm_name         = each.value.name
  talos_version   = var.talos_version
  talos_schematic = var.talos_schematic_id
  datastore       = var.datastore
  iso_datastore   = var.iso_datastore
  bridge_name     = proxmox_network_linux_bridge.lan.name
  vlan_id         = 10
  mac_address     = each.value.mac
}

module "talos_config" {
  source = "../../modules/talos-cluster-config"

  cluster_name        = "talos-cp-1"
  control_plane_nodes = local.talos_nodes          # ✅ correct type: map(object({ ip, mac }))
  # cluster_vip      = "10.10.10.29"               # optional; omit to use the first node IP as endpoint
  talos_version       = var.talos_version
  install_disk        = "/dev/sda"

  depends_on = [module.talos_vms]
}