
output "vm_id" {
  description = "Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "generation" {
  description = "Changes when the Talos version or installation ISO changes."
  value       = terraform_data.generation.id
}
