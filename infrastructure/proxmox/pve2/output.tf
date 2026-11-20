output "worker_name" {
  value = proxmox_virtual_environment_vm.talos_worker.name
}

output "worker_vm_id" {
  value = proxmox_virtual_environment_vm.talos_worker.vm_id
}

output "worker_mac_address" {
  value = var.worker.mac_address
}

output "worker_ip" {
  value       = "10.10.10.31"
  description = "Target Mgmt VLAN IP — set via OPNsense DHCP reservation (talos-wk-1)"
}