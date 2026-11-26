import {
  to = proxmox_virtual_environment_vm.opnsense
  id = "pve1/100"
}

resource "proxmox_virtual_environment_vm" "opnsense" {
  name      = "opnsense"
  vm_id     = 100
  node_name = "pve1"

  description = "OPNsense Router — managed by Terraform"
  tags        = ["router", "opnsense", "terraform"]

  machine = "q35"
  bios    = "ovmf"

  boot_order = ["scsi0", "ide3"]

  started         = true
  stop_on_destroy = true

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  efi_disk {
    datastore_id = var.vm_datastore_id
    type         = "4m"
  }

  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }

  network_device {
    bridge   = proxmox_network_linux_bridge.lan["pve1"].name
    model    = "virtio"
    firewall = false
  }

  cdrom {
    file_id   = "local:iso/OPNsense-26.7-dvd-amd64.iso"
    interface = "ide3"
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = 16
    iothread     = true
    discard      = "on"
  }

  serial_device {}

  lifecycle {
    prevent_destroy = true
  }
}