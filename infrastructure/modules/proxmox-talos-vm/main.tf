
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.114.0"
    }
  }
}

# Preserve previous resource address
moved {
  from = proxmox_virtual_environment_vm.talos_vm
  to   = proxmox_virtual_environment_vm.this
}

# Track changes to the Talos installation image.
# This does NOT destroy the existing VM.
resource "terraform_data" "generation" {
  triggers_replace = [
    var.talos_version,
    var.iso_file_id
  ]
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.vm_name
  vm_id     = var.vm_id
  node_name = var.node_name

  description = "Talos control plane (VLAN ${var.vlan_id}), managed by OpenTofu"

  tags = [
    "talos",
    "control-plane",
    "kubernetes",
    "terraform"
  ]

  machine    = "q35"
  bios       = "seabios"
  boot_order = ["scsi0", "ide2"]

  started         = true
  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = var.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    iothread     = true
    discard      = "on"
    file_format  = "raw"
  }

  cdrom {
    file_id   = var.iso_file_id
    interface = "ide2"
  }

  network_device {
    bridge      = var.bridge_name
    model       = "virtio"
    vlan_id     = var.vlan_id
    mac_address = var.mac_address
  }

  serial_device {}
}
