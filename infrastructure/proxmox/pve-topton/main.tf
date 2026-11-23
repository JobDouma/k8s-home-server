
locals {
  talos_nodes = {
    "cp-topton" = {
      vm_id = 110
      ip    = "10.10.10.30"
      mac   = "BC:24:11:C5:51:77"
    }
  }

  bootstrap_node = "cp-topton"
}

# Talos Image Factory
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.talos_extensions
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}

# Download Talos ISO to Proxmox
resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore_id
  node_name    = var.proxmox_node

  file_name = "talos-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 8)}-nocloud-amd64.iso"

  url = data.talos_image_factory_urls.this.urls.iso
}

# Preserve previous VM module address
moved {
  from = module.talos_vms["cp-1"]
  to   = module.talos_vms["cp-topton"]
}

# Talos VMs
module "talos_vms" {
  source   = "../../modules/proxmox-talos-vm"
  for_each = local.talos_nodes

  node_name       = var.proxmox_node
  vm_id           = each.value.vm_id
  vm_name         = each.key
  talos_version   = var.talos_version
  iso_file_id     = proxmox_download_file.talos_iso.id
  vm_datastore_id = var.vm_datastore_id

  bridge_name = proxmox_network_linux_bridge.lan.name
  vlan_id     = var.mgmt_vlan_id
  mac_address = each.value.mac
}

# Preserve previous cluster module address
moved {
  from = module.talos_config
  to   = module.talos_cluster
}

# Preserve previous machine configuration address
moved {
  from = module.talos_cluster.talos_machine_configuration_apply.controlplane["cp-1"]
  to   = module.talos_cluster.talos_machine_configuration_apply.controlplane["cp-topton"]
}

# Talos cluster
module "talos_cluster" {
  source = "../../modules/talos-cluster"

  cluster_name   = var.cluster_name
  talos_version  = var.talos_version
  bootstrap_node = local.bootstrap_node

  control_plane_nodes = {
    for k, v in local.talos_nodes : k => {
      ip         = v.ip
      generation = module.talos_vms[k].generation
    }
  }
}
