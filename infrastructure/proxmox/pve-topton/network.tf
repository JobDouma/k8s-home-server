# Import the existing VLAN-aware bridge if it was created outside Terraform.
import {
  to = proxmox_network_linux_bridge.lan
  id = "pve1/vmbr1"   # <node_name>/<bridge_name>
}

resource "proxmox_network_linux_bridge" "lan" {
  node_name  = var.proxmox_node
  name       = "vmbr1"
  comment    = "VLAN-aware bridge for house runs (rooms + office uplink)"
  ports      = var.lan_nics
  vlan_aware = true
  vids       = var.vlan_ids

  lifecycle {
    prevent_destroy = true
  }
}