# Adopt the bridge that already exists on pve1. Safe no-op if it is already in state.
import {
  to = proxmox_network_linux_bridge.lan["pve1"]
  id = "pve1:vmbr1"
}

resource "proxmox_network_linux_bridge" "lan" {
  for_each = {
    for k, v in local.proxmox_nodes : k => v
    if v.create_bridge
  }

  node_name  = each.key
  name       = each.value.bridge_name
  comment    = "VLAN-aware bridge for house network"
  ports      = each.value.bridge_ports
  vlan_aware = each.value.bridge_vlan_aware
  vids       = each.value.bridge_vids != null ? join(" ", each.value.bridge_vids) : null

  lifecycle {
    prevent_destroy = true
  }
}