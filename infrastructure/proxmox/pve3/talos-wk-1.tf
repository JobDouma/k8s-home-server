# ─────────────────────────────────────────────────────────────────
# Talos Worker — pve2 (talos-wk-1)
# ─────────────────────────────────────────────────────────────────
# PREREQUISITES before first apply:
#   1. pve2 reachable at ${var.proxmox_endpoint} with the API token.
#   2. vmbr1 exists on pve2 (VLAN-aware, includes VLAN 10).
#   3. infrastructure/opnsense/ has been applied, creating the
#      talos-wk-1 reservation (MAC = ${var.worker.mac_address}, IP 10.10.10.31).
#
# started = false: flip to true (or `qm start 121` on pve2) after
# confirming the DHCP reservation is live in OPNsense.
# ─────────────────────────────────────────────────────────────────

locals {
  talos_iso_url = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/nocloud-amd64.iso"
  iso_filename  = "talos-${var.talos_version}-nocloud-amd64.iso"
}

data "http" "talos_iso_sha256" {
  url = "${local.talos_iso_url}.sha256"
}

locals {
  talos_iso_checksum = regex(
    "^[a-fA-F0-9]{64}",
    trimspace(data.http.talos_iso_sha256.response_body),
  )
}

resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore
  node_name    = var.proxmox_node
  file_name    = local.iso_filename
  url          = local.talos_iso_url

  checksum           = local.talos_iso_checksum
  checksum_algorithm = "sha256"

  lifecycle {
    prevent_destroy = true
  }
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  name      = var.worker.name
  vm_id     = var.worker.vm_id
  node_name = var.proxmox_node

  description = "Talos Worker — ${var.worker.name} on ${var.proxmox_node}"
  tags        = ["talos", "worker", "kubernetes", "terraform"]

  machine    = "q35"
  bios       = "seabios"
  boot_order = ["scsi0", "ide3"]

  started         = false
  stop_on_destroy = true

  startup {
    order    = 1
    up_delay = 30
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [started]
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.worker.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.worker.memory
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = var.worker.disk_size
    iothread     = true
    discard      = "on"
    file_format  = "raw"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide3"
  }

  network_device {
    bridge      = var.lan_bridge
    model       = "virtio"
    vlan_id     = var.worker.vlan_id
    mac_address = var.worker.mac_address
  }

  serial_device {}
}