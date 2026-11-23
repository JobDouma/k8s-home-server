# infrastructure/proxmox/pve-topton/outputs.tf

output "talos_vm_ids" {
  value = { for k, v in module.talos_vms : k => v.vm_id }
}

output "talos_vm_ips" {
  description = "IPs are enforced by OPNsense DHCP reservations."
  value       = { for k, v in local.talos_nodes : v.name => v.ip }
}

output "kubeconfig" {
  description = "Raw kubeconfig. Export: tofu output --raw kubeconfig > ./kubeconfig"
  value       = module.talos_config.kubeconfig
  sensitive   = true
}

output "talosconfig" {
  description = "Raw talosconfig. Export: tofu output --raw talosconfig > ./talosconfig"
  value       = module.talos_config.talosconfig
  sensitive   = true
}

output "machine_secrets" {
  description = "Talos PKI/secrets for disaster recovery. Back up offline; never commit."
  value       = module.talos_config.machine_secrets
  sensitive   = true
}