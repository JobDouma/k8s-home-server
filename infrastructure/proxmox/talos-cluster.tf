resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version

  lifecycle {
    ignore_changes = [talos_version]
  }
}

locals {
  cluster_endpoint = var.cluster_vip != null ? (
    "https://${var.cluster_vip}:6443"
  ) : (
    "https://${local.talos_nodes[local.bootstrap_node].ip}:6443"
  )

  vip_patch = var.cluster_vip != null ? [
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            deviceSelector = { driver = "virtio_net" }
            vip            = { ip = var.cluster_vip }
          }]
        }
      }
    })
  ] : []
}

data "talos_machine_configuration" "this" {
  for_each = local.talos_nodes

  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = local.vip_patch
}

# Ephemeral kubeconfig used only for drain/uncordon during in-place upgrades.
# It never enters state, which is exactly what talos_machine wants.
ephemeral "talos_cluster_kubeconfig" "drain" {
  machine_secrets = talos_machine_secrets.this.machine_secrets
  cluster_name    = var.cluster_name
  endpoint        = local.cluster_endpoint
}

resource "talos_machine" "cp_topton" {
  depends_on = [
    proxmox_virtual_environment_vm.talos["cp-topton"],
  ]

  node = local.talos_nodes["cp-topton"].ip

  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.this["cp-topton"].machine_configuration
  image                 = local.talos_installer_image

  kubeconfig_wo = ephemeral.talos_cluster_kubeconfig.drain.kubeconfig_raw

  # Keep prevent_destroy for routine operations. Remove it only when you
  # intentionally replace this node (disaster recovery / cattle redeploy).
  lifecycle {
    prevent_destroy = true
  }
}

resource "talos_machine" "cp_lenovo" {
  depends_on = [
    proxmox_virtual_environment_vm.talos["cp-lenovo"],
  ]

  node = local.talos_nodes["cp-lenovo"].ip

  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.this["cp-lenovo"].machine_configuration
  image                 = local.talos_installer_image

  kubeconfig_wo = ephemeral.talos_cluster_kubeconfig.drain.kubeconfig_raw

  lifecycle {
    prevent_destroy = true
  }
}

resource "talos_machine" "cp_hp1" {
  depends_on = [
    proxmox_virtual_environment_vm.talos["cp-hp1"],
  ]

  node = local.talos_nodes["cp-hp1"].ip

  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.this["cp-hp1"].machine_configuration
  image                 = local.talos_installer_image

  kubeconfig_wo = ephemeral.talos_cluster_kubeconfig.drain.kubeconfig_raw

  lifecycle {
    prevent_destroy = true
  }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine.cp_topton,
    talos_machine.cp_lenovo,
    talos_machine.cp_hp1,
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_nodes[local.bootstrap_node].ip
}

data "talos_client_configuration" "this" {
  depends_on = [talos_machine_bootstrap.this]

  cluster_name = var.cluster_name

  client_configuration = talos_machine_secrets.this.client_configuration

  endpoints = [for n in local.talos_nodes : n.ip]
  nodes     = [for n in local.talos_nodes : n.ip]
}

# Managed kubeconfig for local_file.kubeconfig and outputs.
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_nodes[local.bootstrap_node].ip

  lifecycle {
    replace_triggered_by = [talos_machine_bootstrap.this]
  }
}