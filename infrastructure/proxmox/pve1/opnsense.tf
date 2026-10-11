# The OPNsense ISO is manually uploaded to `local` storage.
# Official mirrors only serve .iso.bz2, which Proxmox cannot decompress,
# so we reference the uploaded file directly by file_id.

resource "proxmox_virtual_environment_vm" "opnsense" {
  name      = "opnsense"
  vm_id     = 100
  node_name = var.proxmox_node

  description = "OPNsense Router — managed by Terraform"
  tags        = ["router", "opnsense", "terraform"]

  machine = "q35"
  bios    = "ovmf"

  # Disk first, CD as fallback. Prevents installer re-entry on reboot.
  boot_order = ["scsi0", "ide3"]

  started         = true
  stop_on_destroy = true

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
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
  # OPNsense creates VLAN sub-interfaces internally (vtnet1.10, etc.).
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
}