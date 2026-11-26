# pve-topton — Talos control plane on Proxmox

Manages the OPNsense router, the VLAN-aware bridge, and the Talos control-plane
VMs on the `pve1` Proxmox node.

## Apply

    tofu init
    tofu plan
    tofu apply

## Accessing the cluster

After `tofu apply` completes, export the credentials from this directory:

    tofu output --raw kubeconfig   > ./kubeconfig
    tofu output --raw talosconfig  > ./talosconfig

Add both files to `.gitignore` — they contain admin credentials.

### kubectl

    export KUBECONFIG=./kubeconfig
    kubectl get nodes

### talosctl

The generated `talosconfig` lists every control-plane IP as an endpoint, so
`talosctl` fails over automatically if a node is down:

    talosctl --talosconfig ./talosconfig version
    talosctl --talosconfig ./talosconfig -n 10.10.10.30 get members

## Disaster recovery

    tofu output --raw machine_secrets > secrets.json

This is the Talos PKI (CA, keys, bootstrap tokens). Store it offline — if the
cluster is lost and the state is gone, this is the only way to recover it in
place. Never commit it.

## Omni

Not used. The full lifecycle — VM creation → Talos config → bootstrap →
kubeconfig — is handled by OpenTofu. Omni adds a management layer that would
duplicate this; it becomes worthwhile only when you're running many clusters.