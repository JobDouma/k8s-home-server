# ─────────────────────────────────────────────────────────────────
# Networking — PVE2
# ─────────────────────────────────────────────────────────────────
# This file creates vmbr1 (VLAN-aware LAN trunk) for pve2.
# If you already configured vmbr1 manually on pve2, DELETE this file
# and make sure the worker's `bridge = "vmbr1"` still works.
#
# The management bridge vmbr0 is NOT managed here (pre-existing).
# ─────────────────────────────────────────────────────────────────

# Uncomment to let Terraform create vmbr1.
#
# resource "proxmox_network_linux_bridge" "lan" {
#   node_name  = var.proxmox_node
#   name       = "vmbr1"
#   comment    = "VLAN-aware trunk for Talos worker"
#   ports      = ["nic1"]     # ← adjust to your pve2 LAN NIC name
#   vlan_aware = true
#   vids       = "10"
#
#   lifecycle {
#     prevent_destroy = true
#   }
# }