# Proxmox + Talos Home Cluster

Three Proxmox hosts, three Talos Linux control-plane VMs, one OPNsense router VM.
Managed with OpenTofu.

## Layout

| Host | PVE mgmt IP | Talos node | VM ID | Node IP | VLAN |
|---|---|---|---|---|---|
| pve1 (Topton) | 10.10.10.20 | cp-topton | 110 | 10.10.10.30 | 10 (tagged) |
| pve-lenovo    | 10.10.10.21 | cp-lenovo | 120 | 10.10.10.31 | untagged (PVID 10) |
| pve-hp1       | 10.10.10.22 | cp-hp1    | 130 | 10.10.10.32 | untagged (PVID 10) |

- OPNsense runs as VM 100 on `pve1`.
- `pve1` uses a VLAN-aware bridge `vmbr1`. `pve-lenovo` / `pve-hp1` use the default `vmbr0`.
- MAC addresses are declared in `main.tf` (`local.talos_nodes`). They **must** match the OPNsense Kea DHCP reservations for the static-IP bootstrap to work.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Locals, ISO download, image factory schematic |
| `network.tf` | VLAN-aware Linux bridge on `pve1` |
| `talos-vms.tf` | Proxmox VM definitions (for_each) |
| `talos-cluster.tf` | Talos machine config, bootstrap, kubeconfig |
| `opnsense.tf` | OPNsense router VM (protected) |
| `variables.tf` | Inputs (`talos_version`, `vm_revision`, …) |
| `outputs.tf` | Outputs + `local_file.talosconfig` / `local_file.kubeconfig` |
| `versions.tf` | Providers + required versions |
| `terraform.tfvars` | Environment-specific values (git-ignored if it holds secrets) |

## Prerequisites

1. **OpenTofu >= 1.8** and `talosctl` + `kubectl` installed on the workstation.
2. **Proxmox API token** with permissions on VMs, ISO datastore, and network bridge.
3. **Passwordless SSH** from the workstation to each PVE host — required by the
   `terraform_data.enable_agent` provisioner:
   ```bash
   for h in 10.10.10.20 10.10.10.21 10.10.10.22; do
     ssh-copy-id -o StrictHostKeyChecking=accept-new root@$h
     ssh -o BatchMode=yes root@$h 'echo OK'
   done
   ```
4. **Each PVE host can reach `https://factory.talos.dev`** (used by
   `proxmox_download_file`). Verify:
   ```bash
   for h in 10.10.10.20 10.10.10.21 10.10.10.22; do
     ssh root@$h 'curl -fsS -o /dev/null -w "%{http_code}\n" https://factory.talos.dev/'
   done
   ```
5. **OPNsense DHCP reservations** exist for the three Talos MACs (`BC:24:11:C5:51:77/78/79`)
   pointing at `10.10.10.30/31/32`.
6. **`overwrite_unmanaged = true`** is set on `proxmox_download_file.talos_iso`
   in `main.tf`. This lets the provider replace ISOs that were created outside state
   (needed after `tofu state rm` or a wipe).

## First deploy

```bash
cd infrastructure/proxmox
tofu init
tofu validate
tofu plan
tofu apply
```

The apply performs, in order:

1. `proxmox_download_file.talos_iso["pve1"|"pve-lenovo"|"pve-hp1"]` — each PVE node downloads the ISO.
2. `proxmox_virtual_environment_vm.talos["cp-*"]` — VM created with `agent.enabled = false` (avoids the maintenance-mode agent hang).
3. `talos_machine.this["cp-*"]` — config applied: static IP, default route, `HostnameConfig{hostname: <node>, auto: off}`, optional VIP.
4. `terraform_data.enable_agent["cp-*"]` — SSHes to each PVE host, runs `qm set <vmid> --agent enabled=1 && qm reboot <vmid>`.
5. `talos_machine_bootstrap.this` — initialises etcd on `cp-topton`.
6. `talos_cluster_kubeconfig.this` + `local_file.*` — writes `./talosconfig` and `./kubeconfig`.

Verify the cluster:

```bash
talosctl --talosconfig ./talosconfig -n 10.10.10.30 health
kubectl --kubeconfig ./kubeconfig get nodes -o wide
```

> **Important**: leave `drain_on_upgrade = false` in `talos_machine.this` for the first
> bootstrap. The provider (v0.12.x) tries to cordon/drain every node before applying
> config, which fails because Kubernetes is not up yet. Set `drain_on_upgrade = true`
> *after* the cluster is healthy for day-2 upgrades.

> **Timing**: `kubectl get nodes` may return `connection refused` for 60–90 seconds
> after `tofu apply` finishes. The three VMs are rebooting after the agent-enable step.
> Wait, then retry.

## Daily operations

```bash
tofu plan
tofu apply
```

## Full wipe / redeploy

Bump `vm_revision` in `terraform.tfvars` (e.g. `1` → `2`) and apply:

```bash
# terraform.tfvars
# vm_revision = 2

tofu apply
```

This destroys and recreates every Talos VM, re-installs Talos, re-enables the guest
agent, and re-bootstraps the cluster. **OPNsense and the Linux bridge are untouched**
(`prevent_destroy = true` on those).

Alternative one-off replace (no file edit):

```bash
tofu apply \
  -replace='proxmox_virtual_environment_vm.talos["cp-topton"]' \
  -replace='proxmox_virtual_environment_vm.talos["cp-lenovo"]' \
  -replace='proxmox_virtual_environment_vm.talos["cp-hp1"]'
```

## Update only Lenovo or HP1

`-target` is for repair and partial rollouts. Do **not** use it for routine full applies.

### Lenovo only

```bash
tofu apply \
  -target='proxmox_download_file.talos_iso["pve-lenovo"]' \
  -target='proxmox_virtual_environment_vm.talos["cp-lenovo"]' \
  -target='talos_machine.this["cp-lenovo"]' \
  -target='terraform_data.enable_agent["cp-lenovo"]'
```

### HP1 only

```bash
tofu apply \
  -target='proxmox_download_file.talos_iso["pve-hp1"]' \
  -target='proxmox_virtual_environment_vm.talos["cp-hp1"]' \
  -target='talos_machine.this["cp-hp1"]' \
  -target='terraform_data.enable_agent["cp-hp1"]'
```

### Topton only

```bash
tofu apply \
  -target='proxmox_download_file.talos_iso["pve1"]' \
  -target='proxmox_virtual_environment_vm.talos["cp-topton"]' \
  -target='talos_machine.this["cp-topton"]' \
  -target='terraform_data.enable_agent["cp-topton"]'
```

`-target` does **not** include downstream dependencies. If you need to also
re-bootstrap or regenerate kubeconfig for the targeted node, add the corresponding
`-target='talos_machine_bootstrap.this'` / `-target='talos_cluster_kubeconfig.this'`.

## Version management and updates

### Talos OS upgrade

1. Bump `talos_version` in `terraform.tfvars`.
2. Plan first, then apply **one node at a time**:

```bash
tofu plan
tofu apply -target='talos_machine.this["cp-lenovo"]'
talosctl --talosconfig ./talosconfig -n 10.10.10.31 health
# then repeat for cp-hp1 and cp-topton
```

3. Never upgrade all control-plane nodes in parallel — you risk losing etcd quorum.

Talos only guarantees transparent config migration between **adjacent minor versions**.
For multi-minor jumps (e.g. `1.12 → 1.14`), go one minor at a time: `1.12 → 1.13 → 1.14`,
each to the latest patch of that minor.

### Kubernetes upgrade

Kubernetes is upgraded via `talosctl upgrade-k8s`, not by changing Terraform.

```bash
talosctl --talosconfig ./talosconfig -n 10.10.10.30 upgrade-k8s --to 1.38.0 --dry-run
talosctl --talosconfig ./talosconfig -n 10.10.10.30 upgrade-k8s --to 1.38.0
```

The `upgrade-k8s` command rolls all nodes; `--nodes` selects the control-plane node
used to run the operation. Do this **after** the Talos OS upgrade has completed and
the cluster reports healthy.

### System extensions

Change `talos_extensions` in `variables.tf`. The image-factory schematic hash changes,
so `local.talos_installer_image` changes, and `talos_machine` performs an OS upgrade
with the new extensions on the next apply. Roll out one node at a time.

## Recover `talosconfig` / `kubeconfig` if files are lost

The real trust root is `talos_machine_secrets.this`, stored in OpenTofu state and
in the `machine_secrets` output. `talosconfig` and `kubeconfig` are regenerable client
credentials — they are not the source of truth.

### If the OpenTofu state is intact

```bash
cd infrastructure/proxmox
tofu output -raw talosconfig > talosconfig
tofu output -raw kubeconfig > kubeconfig
chmod 600 talosconfig kubeconfig
```

Or regenerate kubeconfig from talosconfig:

```bash
talosctl --talosconfig ./talosconfig -n 10.10.10.30 kubeconfig ./kubeconfig
```

### If both state and `machine_secrets` are lost

The cluster PKI is unrecoverable. Rebuild from scratch:

```bash
# 1. Back up terraform.tfstate, then remove it
mv terraform.tfstate terraform.tfstate.broken

# 2. Purge the VMs on each PVE host
ssh root@10.10.10.20 'qm stop 110 || true; qm destroy 110 --purge'
ssh root@10.10.10.21 'qm stop 120 || true; qm destroy 120 --purge'
ssh root@10.10.10.22 'qm stop 130 || true; qm destroy 130 --purge'

# 3. Re-apply from scratch
tofu init
tofu apply
```

### Recommended offline backups

- `tofu output -json machine_secrets > machine_secrets.json && chmod 600 machine_secrets.json`
- Copy `terraform.tfstate` (encrypted) after every meaningful change.
- `talosctl etcd snapshot` periodically for disaster recovery of etcd itself.

## Troubleshooting

### Apply appears stuck during refresh

If `tofu apply` sits at `Still creating…` or `Refreshing state…` for more than 5 minutes:

```bash
# Kill the process (Ctrl+C twice if needed), then inspect state (no refresh, instant):
tofu state list
```

If the state contains a resource that no longer exists on Proxmox or has
`agent.enabled = true` (waiting on a guest agent that never comes up), remove it:

```bash
tofu state rm 'proxmox_virtual_environment_vm.talos["cp-hp1"]'
```

Then clean up the leftover VM and re-apply.

### Talos config fails with "static hostname is already set"

You set `machine.network.hostname` in the patch **and** the default `HostnameConfig`
document exists. Fix: use a dedicated `HostnameConfig` document with `auto: "off"`
(already in `talos-cluster.tf` in the correct config).

### Talos config fails with "'auto' and 'hostname' cannot be set at the same time"

The `HostnameConfig` document must include `auto: "off"` alongside `hostname`.
This is the fix in the current `talos-cluster.tf`.

### `draining node: … connection refused` on first bootstrap

`drain_on_upgrade = true` triggers a cordon/drain before the Kubernetes API exists.
Set `drain_on_upgrade = false` in `talos_machine.this` for the first apply.
Re-enable it after the cluster is healthy.

### `terraform_data.enable_agent` hangs

Passwordless SSH from the workstation to `root@<pve-mgmt-ip>` is broken. Test each:

```bash
for h in 10.10.10.20 10.10.10.21 10.10.10.22; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 root@$h 'echo OK' || echo "FAIL $h"
done
```

Common cause: `ssh-agent` not loaded in the shell running `tofu apply`.

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ssh-add -l   # must list at least one key
```

### Proxmox guest agent reports no IP / no hostname

Verify the agent extension is running on the node:

```bash
talosctl --talosconfig ./talosconfig -n 10.10.10.32 get extensions
talosctl --talosconfig ./talosconfig -n 10.10.10.32 service ext-qemu-guest-agent status
```

Verify the Proxmox side:

```bash
ssh root@10.10.10.22 'qm config 130 | grep agent'      # should show agent: 1
ssh root@10.10.10.22 'qm agent 130 ping'               # should return OK
ssh root@10.10.10.22 'qm agent 130 network-get-interfaces'
```

If `qm config` shows `agent: 1` but `qm agent ping` fails, the guest agent extension
is not running inside Talos. Reboot the VM once Talos is healthy.

### `tofu apply` fails with "File already exists in the datastore"

The ISO exists on the PVE host but is not tracked by OpenTofu state
(e.g. after `tofu state rm`). Fix in `main.tf`:

```hcl
resource "proxmox_download_file" "talos_iso" {
  for_each = local.iso_download_nodes
  # …
  overwrite           = true
  overwrite_unmanaged = true   # ← add this
}
```

Or delete the ISO from the PVE host:

```bash
ssh root@10.10.10.20 'rm -f /var/lib/template/iso/talos-*.iso'
ssh root@10.10.10.21 'rm -f /var/lib/template/iso/talos-*.iso'
ssh root@10.10.10.22 'rm -f /var/lib/template/iso/talos-*.iso'
```

### `kubectl` returns `connection refused` right after apply

The three VMs are still rebooting after the agent-enable step. Wait 60–90 seconds
and retry. Check Talos-side health in the meantime:

```bash
talosctl --talosconfig ./talosconfig -n 10.10.10.30 health
talosctl --talosconfig ./talosconfig -n 10.10.10.30 etcd members
talosctl --talosconfig ./talosconfig -n 10.10.10.30 service kube-apiserver status
```

If it is still refusing after 2 minutes, re-bootstrap:

```bash
tofu apply -replace='talos_machine_bootstrap.this'
```

### `iothread is only valid with virtio disk …` warning

Cosmetic. The disk is already `virtio` (`scsi0` with `virtio-scsi-pci`). Safe to ignore.

### `-target` errors with "No matching objects found"

The resource is not in state. This is normal right after `tofu state rm` or on a
fresh deploy. Run `tofu state list` to see what actually exists, then adjust the
`-target` address.