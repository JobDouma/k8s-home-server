terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.114.0"
    }
  }
}

resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore
  node_name    = var.node_name
  file_name    = "talos-${var.talos_version}-nocloud-amd64.iso"
  url          = "https://factory.talos.dev/image/${var.talos_schematic}/${var.talos_version}/nocloud-amd64.iso"

  # Keep prevent_destroy only on the OPNsense VM and the network bridge — those are your pets. 
  # The Talos VM and ISO are cattle.
}

resource "proxmox_virtual_environment_vm" "talos_vm" {
  name      = var.vm_name
  vm_id     = var.vm_id
  node_name = var.node_name

  description = "Talos Control Plane — Mgmt VLAN ${var.vlan_id}"
  tags        = ["talos", "control-plane", "kubernetes", "terraform"]

  machine    = "q35"
  bios       = "seabios"
  boot_order = ["scsi0", "ide3"]

  started         = false
  stop_on_destroy = true

  lifecycle {
    # prevent_destroy = true
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
    bridge      = var.bridge_name
    model       = "virtio"
    vlan_id     = var.vlan_id
    mac_address = var.mac_address
  }

  serial_device {}

  # Ensure the ISO is fully downloaded before the VM is created.
  depends_on = [proxmox_download_file.talos_iso]
}