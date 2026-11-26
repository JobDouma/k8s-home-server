resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.talos_nodes

  name      = each.key
  vm_id     = each.value.vm_id
  node_name = each.value.proxmox_node

  description = "Talos control plane (VLAN ${each.value.vlan_id}), managed by OpenTofu"
  tags        = ["talos", "control-plane", "kubernetes", "terraform"]

  machine    = "q35"
  bios       = "seabios"
  boot_order = ["scsi0", "ide2"]

  started         = true
  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = 100
    iothread     = true
    discard      = "on"
    file_format  = "raw"
  }

  cdrom {
    file_id   = local.talos_iso_file_ids[each.value.proxmox_node]
    interface = "ide2"
  }

  network_device {
    bridge      = local.proxmox_nodes[each.value.proxmox_node].bridge_name
    model       = "virtio"
    vlan_id     = each.value.vlan_id
    mac_address = each.value.mac
  }

  serial_device {}
}