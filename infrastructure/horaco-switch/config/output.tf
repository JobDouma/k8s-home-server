output "switch_host" {
  value       = var.switch_host
  description = "Management IP (on the mgmt VLAN SVI)."
}

output "mgmt_vlan" {
  value       = var.mgmt_vlan
  description = "VLAN carrying the switch management IP."
}

output "trunk_port" {
  value       = var.uplink_port
  description = "SFP+ trunk port carrying tagged VLANs 10–50 to OPNsense."
}

output "mgmt_ports" {
  value       = var.vlan_port_map["10"]
  description = "Copper ports untagged on MGMT VLAN (VLAN 10)."
}

output "home_ports" {
  value       = var.vlan_port_map["30"]
  description = "Copper ports untagged on HOME VLAN (VLAN 30)."
}

output "lag_config" {
  value       = var.lag_port_map
  description = "LAG definitions (empty by default)."
}