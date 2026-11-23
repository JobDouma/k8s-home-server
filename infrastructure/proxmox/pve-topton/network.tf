resource "proxmox_network_linux_bridge" "lan" {
  node_name  = var.proxmox_node
  name       = "vmbr1"
  comment    = "VLAN-aware bridge for house runs (rooms + office uplink)"
  ports      = var.lan_nics
  vlan_aware = true
  vids       = join(" ", var.vlan_ids)

  lifecycle {
    prevent_destroy = true
  }
}