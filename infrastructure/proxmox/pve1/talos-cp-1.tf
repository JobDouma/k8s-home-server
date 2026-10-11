resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node
  file_name    = "talos-omni-amd64.iso"
  url          = "https://factory.talos.dev/image/46a5ffcc6627ec9bf37c6b2f13b290000d5ac2981e90b7160b5f2878f375ee8c/v1.14.2/nocloud-amd64.iso"
}

resource "proxmox_virtual_environment_vm" "talos_cp_1" {
  name      = "talos-cp-1"
  vm_id     = 110
  node_name = var.proxmox_node

  description = "Talos Control Plane 1 — Mgmt VLAN 10"
  tags        = ["talos", "control-plane", "kubernetes", "terraform"]

  machine = "q35"
  bios    = "seabios"

  # Disk first; Talos' nocloud image installs itself and reboots into disk.
  boot_order = ["scsi0", "ide3"]

  started         = false   # start manually after OPNsense is routing VLAN 10
  stop_on_destroy = true

  agent {
    enabled = true
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"   # REQUIRED for Talos
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

  # Single NIC on VLAN 10 via the VLAN-aware bridge.
  network_device {
    bridge  = proxmox_network_linux_bridge.lan.name
    model   = "virtio"
    vlan_id = 10
  }

  serial_device {}
}