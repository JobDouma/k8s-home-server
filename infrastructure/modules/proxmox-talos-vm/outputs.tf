output "vm_id" {
  value = proxmox_virtual_environment_vm.talos_vm.vm_id
}

output "vm_ip" {
  description = "IP is managed externally via DHCP reservation."
  value       = "Assigned via OPNsense DHCP reservation"
}