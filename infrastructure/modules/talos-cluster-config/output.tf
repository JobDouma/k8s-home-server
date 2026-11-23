output "kubeconfig" {
  description = "Raw kubeconfig for kubectl."
  value       = data.talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Raw talosconfig for talosctl."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "machine_secrets" {
  description = "Generated machine secrets (sensitive). Keep these for disaster recovery."
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}