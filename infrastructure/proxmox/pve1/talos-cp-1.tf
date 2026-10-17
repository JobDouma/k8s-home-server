# ─────────────────────────────────────────────────────────────────
# Talos Control Plane 1 — PVE1
# ─────────────────────────────────────────────────────────────────
# The ISO is fetched from the Talos Image Factory and verified
# against the .sha256 sidecar published next to it. A truncated or
# corrupted download fails `tofu apply` instead of booting a broken
# VM.
#
# started = false on purpose: the CP boots AFTER OPNsense is routing
# VLAN 10 (it needs DHCP to get 10.10.10.30 from the reservation).
# Start it manually once `tofu apply` in infrastructure/opnsense/
# has confirmed the MGMT VLAN is live.
# ─────────────────────────────────────────────────────────────────

locals {
  talos_iso_url = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/nocloud-amd64.iso"
  iso_filename  = "talos-${var.talos_version}-nocloud-amd64.iso"
}

data "http" "talos_iso_sha256" {
  url = "${local.talos_iso_url}.sha256"
}

locals {
  # .sha256 is either "hash" or "hash  filename"; extract the leading 64-hex digest.
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

resource "proxmox_virtual_environment_vm" "talos_cp_1" {
  name      = "talos-cp-1"
  vm_id     = 110
  node_name = var.proxmox_node

  description = "Talos Control Plane 1 — Mgmt VLAN 10"
  tags        = ["talos", "control-plane", "kubernetes", "terraform"]

  machine    = "q35"
  bios       = "seabios"
  boot_order = ["scsi0", "ide3"]

  started         = false
  stop_on_destroy = true

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [started]
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = 100
    iothread     = true
    discard      = "on"
    file_format  = "raw"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide3"
  }

  network_device {
    bridge  = proxmox_network_linux_bridge.lan.name
    model   = "virtio"
    vlan_id = 10
  }

  serial_device {}
}