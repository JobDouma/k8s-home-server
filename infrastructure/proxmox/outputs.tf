output "talos_vm_ids" {
  value = { for k, v in proxmox_virtual_environment_vm.talos : k => v.vm_id }
}

output "talos_vm_ips" {
  value = { for k, v in local.talos_nodes : k => v.ip }
}

output "talos_installer_image" {
  value = local.talos_installer_image
}

output "kubeconfig" {
  sensitive = true
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
}

output "talosconfig" {
  sensitive = true
  value     = data.talos_client_configuration.this.talos_config
}

output "machine_secrets" {
  description = "Talos PKI and machine secrets. Back up offline."
  sensitive   = true
  value       = talos_machine_secrets.this.machine_secrets
}

resource "local_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.module}/talosconfig"
  file_permission = "0600"
}

resource "local_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}