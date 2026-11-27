locals {
  # All nodes use the same download method now — no upload, no local cache.
  proxmox_nodes = {
    pve1 = {
      bridge_name       = "vmbr1"
      bridge_ports      = ["nic1", "nic2", "nic3", "nic4", "nic5"]
      bridge_vlan_aware = true
      bridge_vids       = [10, 20, 30, 40, 50]
      create_bridge     = true
      iso_via           = "download"
      management_ip     = "10.10.10.20"
    }
    pve-lenovo = {
      bridge_name       = "vmbr0"
      bridge_ports      = null
      bridge_vlan_aware = false
      bridge_vids       = null
      create_bridge     = false
      iso_via           = "download"
      management_ip     = "10.10.10.21"
    }
    pve-hp1 = {
      bridge_name       = "vmbr0"
      bridge_ports      = null
      bridge_vlan_aware = false
      bridge_vids       = null
      create_bridge     = false
      iso_via           = "download"
      management_ip     = "10.10.10.22"
    }
  }

  talos_nodes = {
    cp-topton = {
      vm_id        = 110
      ip           = "10.10.10.30"
      mac          = "BC:24:11:C5:51:77"
      proxmox_node = "pve1"
      vlan_id      = 10
    }
    cp-lenovo = {
      vm_id        = 120
      ip           = "10.10.10.31"
      mac          = "BC:24:11:C5:51:78"
      proxmox_node = "pve-lenovo"
      vlan_id      = null
    }
    cp-hp1 = {
      vm_id        = 130
      ip           = "10.10.10.32"
      mac          = "BC:24:11:C5:51:79"
      proxmox_node = "pve-hp1"
      vlan_id      = null
    }
  }

  bootstrap_node = "cp-topton"

  talos_installer_image = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"
  talos_iso_filename    = "talos-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 8)}-nocloud-amd64.iso"
  talos_iso_url         = data.talos_image_factory_urls.this.urls.iso

  # All nodes download their own ISO.
  iso_download_nodes = toset(keys(local.proxmox_nodes))
}

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

resource "proxmox_download_file" "talos_iso" {
  for_each = local.iso_download_nodes

  content_type = "iso"
  datastore_id = var.iso_datastore_id
  node_name    = each.key
  file_name    = local.talos_iso_filename
  url          = local.talos_iso_url
  verify       = false
  overwrite           = true
  overwrite_unmanaged = true      # ← add this
}

locals {
  talos_iso_file_ids = { for k, v in proxmox_download_file.talos_iso : k => v.id }
}