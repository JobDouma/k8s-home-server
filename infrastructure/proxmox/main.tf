locals {
  proxmox_nodes = {
    pve1 = {
      bridge_name       = "vmbr1"
      bridge_ports      = ["nic1", "nic2", "nic3", "nic4", "nic5"]
      bridge_vlan_aware = true
      bridge_vids       = [10, 20, 30, 40, 50]
      create_bridge     = true
    }
    pve-lenovo = {
      bridge_name       = "vmbr0"
      bridge_ports      = null
      bridge_vlan_aware = false
      bridge_vids       = null
      create_bridge     = false
    }
    pve-hp1 = {
      bridge_name       = "vmbr0"
      bridge_ports      = null
      bridge_vlan_aware = false
      bridge_vids       = null
      create_bridge     = false
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
      vlan_id      = 10
    }
    cp-hp1 = {
      vm_id        = 130
      ip           = "10.10.10.32"
      mac          = "BC:24:11:C5:51:79"
      proxmox_node = "pve-hp1"
      vlan_id      = 10
    }
  }

  bootstrap_node = "cp-topton"

  talos_installer_image = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"
  talos_iso_filename    = "talos-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 8)}-nocloud-amd64.iso"

  # Nodes where Proxmox's own "download from URL" fails the TLS check.
  # For these, tofu downloads the ISO locally and uploads it via scp instead.
  iso_scp_nodes   = toset(["pve-lenovo", "pve-hp1"])
  iso_cache_path  = "${path.module}/.cache/${local.talos_iso_filename}"

  # One lookup table: node name -> ISO file id (works for both methods).
  # For pve1 the ID comes from the download resource; for the scp nodes
  # we construct the standard Proxmox ISO path.
  talos_iso_file_ids = merge(
    { for k, v in proxmox_download_file.talos_iso : k => v.id },
    { for k in local.iso_scp_nodes : k => "local:iso/${local.talos_iso_filename}" },
  )
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

# Works: pve1 uses Proxmox's built-in downloader.
resource "proxmox_download_file" "talos_iso" {
  for_each = {
    for k, v in local.proxmox_nodes : k => v
    if !contains(local.iso_scp_nodes, k)
  }

  content_type = "iso"
  datastore_id = var.iso_datastore_id
  node_name    = each.key
  file_name    = local.talos_iso_filename
  url          = data.talos_image_factory_urls.this.urls.iso
  verify       = false
}

# Download the ISO once on the machine running tofu.
resource "terraform_data" "talos_iso_local" {
  triggers_replace = [data.talos_image_factory_urls.this.urls.iso]

  provisioner "local-exec" {
    command = "mkdir -p '${path.module}/.cache' && curl -fsSL --retry 3 -o '${local.iso_cache_path}.tmp' '${data.talos_image_factory_urls.this.urls.iso}' && mv '${local.iso_cache_path}.tmp' '${local.iso_cache_path}'"
  }
}

# Copy the ISO to pve-lenovo and pve-hp1 using scp.
# This avoids the provider's SSL-verified datastore listing that fails on these nodes.
resource "terraform_data" "talos_iso_scp" {
  for_each = local.iso_scp_nodes

  triggers_replace = [local.iso_cache_path]

  provisioner "local-exec" {
    # Assumes the Proxmox nodes are reachable via SSH as root.
    # The provider block already configures ssh { agent = true, username = "root" }.
    command = "scp -o StrictHostKeyChecking=no '${local.iso_cache_path}' root@${each.key}:/var/lib/vz/template/iso/${local.talos_iso_filename}"
  }

  depends_on = [terraform_data.talos_iso_local]
}