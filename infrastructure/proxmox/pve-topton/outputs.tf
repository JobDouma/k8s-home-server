output "talos_vm_ids" {
  value = { for k, v in module.talos_vms : k => v.vm_id }
}

output "talos_vm_ips" {
  description = "IPs are set via OPNsense DHCP reservations."
  value = {
    "talos-cp-1" = "10.10.10.30"
  }
}