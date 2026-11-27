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

  # Static IP + hostname + default route (+ VIP if set) baked into each
  # node's machine config. Makes nodes self-contained after install; DHCP
  # from OPNsense is only used for the initial maintenance-mode boot.
  talos_node_patches = {
    for k, v in local.talos_nodes : k => [
      yamlencode({
        machine = {
          network = {
            hostname = k
            interfaces = [merge(
              {
                deviceSelector = { driver = "virtio_net" }
                dhcp           = false
                addresses      = ["${v.ip}/24"]
                routes = [{
                  network = "0.0.0.0/0"
                  gateway = var.network_gateway
                }]
              },
              var.cluster_vip != null ? { vip = { ip = var.cluster_vip } } : {}
            )]
          }
        }
      }),
    ]
  }
}

data "talos_machine_configuration" "this" {
  for_each = local.talos_nodes

  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = local.talos_node_patches[each.key]
}

ephemeral "talos_cluster_kubeconfig" "drain" {
  machine_secrets = talos_machine_secrets.this.machine_secrets
  cluster_name    = var.cluster_name
  endpoint        = local.cluster_endpoint
}

resource "talos_machine" "this" {
  for_each = local.talos_nodes

  node = each.value.ip

  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.this[each.key].machine_configuration
  image                 = local.talos_installer_image

  kubeconfig_wo = ephemeral.talos_cluster_kubeconfig.drain.kubeconfig_raw

  depends_on = [
    proxmox_virtual_environment_vm.talos,
  ]

  lifecycle {
    replace_triggered_by = [terraform_data.vm_revision]
  }
}

# Runs after Talos is installed on each node, then flips Proxmox's agent
# flag on and reboots the VM. The qemu-guest-agent extension in Talos
# will start on this boot and populate IPs/hostnames in the UI.
resource "terraform_data" "enable_agent" {
  for_each = local.talos_nodes

  depends_on = [talos_machine.this]

  triggers_replace = [
    terraform_data.vm_revision.id,
    proxmox_virtual_environment_vm.talos[each.key].id,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -eu
      HOST="${local.proxmox_nodes[each.value.proxmox_node].management_ip}"
      VMID="${each.value.vm_id}"
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          root@$HOST \
          "qm set $VMID --agent enabled=1 && qm reboot $VMID"
    EOT
  }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_nodes[local.bootstrap_node].ip

  lifecycle {
    replace_triggered_by = [terraform_data.vm_revision]
  }
}

data "talos_client_configuration" "this" {
  depends_on = [talos_machine_bootstrap.this]

  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration

  endpoints = [for n in local.talos_nodes : n.ip]
  nodes     = [for n in local.talos_nodes : n.ip]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_nodes[local.bootstrap_node].ip

  lifecycle {
    replace_triggered_by = [talos_machine_bootstrap.this]
  }
}