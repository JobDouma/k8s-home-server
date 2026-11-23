# Import the already-running OPNsense VM (VM ID 100) into Terraform state.
# This MUST be done before any apply that includes this resource.
import {
  to = proxmox_virtual_environment_vm.opnsense
  id = "pve1/100"   # <node_name>/<vm_id>
}

resource "proxmox_virtual_environment_vm" "opnsense" {
  name      = "opnsense"
  vm_id     = 100
  node_name = var.proxmox_node

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
    datastore_id = var.datastore
    type         = "4m"
  }

  # NIC 1: WAN — uses the EXISTING vmbr0 (bridged to nic0).
  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }

  # NIC 2: LAN trunk on the new VLAN-aware bridge.
  network_device {
    bridge   = proxmox_network_linux_bridge.lan.name
    model    = "virtio"
    firewall = false
  }

  cdrom {
    file_id   = "local:iso/OPNsense-26.7-dvd-amd64.iso"
    interface = "ide3"
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = 16
    iothread     = true
    discard      = "on"
  }

  serial_device {}

  lifecycle {
    prevent_destroy = true

    # After the import, if the plan shows diffs on MAC addresses
    # (they are assigned by Proxmox, not by Terraform), uncomment:
    # ignore_changes = [
    #   network_device[0].mac_address,
    #   network_device[1].mac_address,
    # ]
  }
}