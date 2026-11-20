output "switch_new_ip" {
  description = "The new management IP that was configured."
  value       = var.switch_new_ip
}

output "switch_ssh_command" {
  description = "Ready-to-run SSH command for the new IP."
  value       = "ssh -oHostKeyAlgorithms=+ssh-rsa ${var.switch_user}@${var.switch_new_ip}"
}

output "switch_web_url" {
  description = "Web UI URL for the new IP."
  value       = "http://${var.switch_new_ip}"
}
