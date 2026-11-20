output "switch_host" {
  value       = var.switch_host
  description = "Management IP (now on the mgmt VLAN SVI only)."
}

output "mgmt_vlan" {
  value       = var.mgmt_vlan
  description = "VLAN carrying the switch management IP."
}

output "trunk_port" {
  value       = var.uplink_port
  description = "SFP+ trunk port carrying tagged VLANs 10–50."
}

output "access_ports" {
  value       = var.vlan_port_map
  description = "Copper ports and their TRUE untagged hybrid VLAN assignment. MGI1–MGI8 are all MGMT."
}

output "lag_config" {
  value       = var.lag_port_map
  description = "LAG definitions (empty by default — MGI2/MGI3 are standalone MGMT)."
}