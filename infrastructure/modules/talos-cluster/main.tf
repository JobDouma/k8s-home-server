
terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12.0"
    }
  }
}

locals {
  bootstrap_ip = var.control_plane_nodes[var.bootstrap_node].ip

  endpoint_ips = [
    for k in sort(keys(var.control_plane_nodes)) :
    var.control_plane_nodes[k].ip
  ]

  cluster_endpoint = var.cluster_vip != null ? (
    "https://${var.cluster_vip}:6443"
  ) : (
    "https://${local.bootstrap_ip}:6443"
  )

  vip_patch = var.cluster_vip != null ? [
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            deviceSelector = {
              driver = "virtio_net"
            }

            vip = {
              ip = var.cluster_vip
            }
          }]
        }
      }
    })
  ] : []
}

# Talos machine secrets
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version

  # Preserve existing cluster identity during version changes.
  lifecycle {
    ignore_changes = [talos_version]
  }
}

# Track node VM generations.
resource "terraform_data" "node_generation" {
  for_each = var.control_plane_nodes

  triggers_replace = [
    each.value.generation
  ]
}

# Generate control-plane configuration.
data "talos_machine_configuration" "controlplane" {
  for_each = var.control_plane_nodes

  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = local.vip_patch
}

# Apply machine configuration.
resource "talos_machine_configuration_apply" "controlplane" {
  for_each = var.control_plane_nodes

  client_configuration = (
    talos_machine_secrets.this.client_configuration
  )

  machine_configuration_input = (
    data.talos_machine_configuration.controlplane[each.key].machine_configuration
  )

  node = each.value.ip

  apply_mode = "auto"

  lifecycle {
    replace_triggered_by = [
      terraform_data.node_generation[each.key]
    ]
  }
}

# Bootstrap the cluster once.
resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.controlplane
  ]

  client_configuration = (
    talos_machine_secrets.this.client_configuration
  )

  node = local.bootstrap_ip
}

# Generate Talos client configuration.
data "talos_client_configuration" "this" {
  depends_on = [
    talos_machine_bootstrap.this
  ]

  cluster_name = var.cluster_name

  client_configuration = (
    talos_machine_secrets.this.client_configuration
  )

  endpoints = local.endpoint_ips
  nodes     = local.endpoint_ips
}

# Generate Kubernetes kubeconfig.
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this
  ]

  client_configuration = (
    talos_machine_secrets.this.client_configuration
  )

  node = local.bootstrap_ip

  lifecycle {
    replace_triggered_by = [
      talos_machine_bootstrap.this
    ]
  }
}
