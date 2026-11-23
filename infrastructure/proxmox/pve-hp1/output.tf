output "talos_vm_ids" {
  value = { for k, v in module.talos_vms : k => v.vm_id }
}

output "talos_vm_ips" {
  description = "IPs are enforced by OPNsense DHCP reservations."
  value       = { for k, v in local.talos_nodes : v.name => v.ip }
}