
output "talos_vm_ids" {
  description = "Talos Proxmox VM IDs."
  value = {
    for k, v in module.talos_vms : k => v.vm_id
  }
}

output "talos_vm_ips" {
  description = "Talos node IPs managed through OPNsense DHCP reservations."
  value = {
    for k, v in local.talos_nodes : k => v.ip
  }
}

output "kubeconfig" {
  description = "Raw kubeconfig for kubectl."
  value       = module.talos_cluster.kubeconfig
  sensitive   = true
}

output "talosconfig" {
  description = "Raw talosconfig for talosctl."
  value       = module.talos_cluster.talosconfig
  sensitive   = true
}

output "machine_secrets" {
  description = "Talos PKI and machine secrets. Back up offline."
  value       = module.talos_cluster.machine_secrets
  sensitive   = true
}
