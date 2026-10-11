output "opnsense_vm_id" {
  value = proxmox_virtual_environment_vm.opnsense.vm_id
}

output "talos_cp_1_vm_id" {
  value = proxmox_virtual_environment_vm.talos_cp_1.vm_id
}

output "talos_cp_1_ip" {
  value       = "10.10.10.30"
  description = "Target Mgmt VLAN IP — set via OPNsense DHCP reservation"
}