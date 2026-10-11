# NOTE: vmbr0 already exists on PVE1 (bridged to nic0, carries mgmt IP).
# It is NOT managed by Terraform — we reference it by name only in VM
# resources. This avoids recreating the bridge and losing management access.

# LAN — one VLAN-aware bridge for ALL house-facing NICs.
resource "proxmox_network_linux_bridge" "lan" {
  node_name  = var.proxmox_node
  name       = "vmbr1"
  comment    = "VLAN-aware bridge for house runs (rooms + office uplink)"
  ports      = var.lan_nics
  vlan_aware = true
  vids       = var.vlan_ids
}