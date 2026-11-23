terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12.0"
    }
  }
}

locals {
  control_plane_ips = values(var.control_plane_nodes)[*].ip
  cluster_endpoint  = var.cluster_vip != null ? "https://${var.cluster_vip}:6443" : "https://${local.control_plane_ips[0]}:6443"

  # Build a config patch that enables the VIP on every control-plane node.
  vip_patch = var.cluster_vip != null ? [yamlencode({
    machine = {
      network = {
        interfaces = [{
          deviceSelector = { driver = "virtio_net" }
          vip = {
            ip = var.cluster_vip
          }
        }]
      }
    }
  })] : []
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version

  lifecycle {
    # Critical: do NOT regenerate the PKI when the version variable is bumped.
    # New clusters pick up the new version; existing clusters keep their original secrets.
    ignore_changes = [talos_version]
  }
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = concat(
    [
      yamlencode({
        machine = {
          install = {
            disk  = var.install_disk
            image = "ghcr.io/siderolabs/installer:${var.talos_version}"
          }
        }
      })
    ],
    local.vip_patch
  )
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each = var.control_plane_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip
  apply_mode                  = "staged_if_needing_reboot"
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.control_plane_ips[0]   # first node in the map (by key sort)
}

data "talos_client_configuration" "this" {
  depends_on = [talos_machine_bootstrap.this]

  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips    # all control-plane IPs, for HA failover
  nodes                = local.control_plane_ips    # talosctl can target any node
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.control_plane_ips[0]
}