# horaco-switch

Terraform-based **disaster-recovery** automation for the
Horaco ZX-SWTG3624AS managed switch (KT-NOS firmware, Realtek-based CLI).

After a factory reset the switch boots at `192.168.2.1` with SSH disabled.
This repo runs the same CLI commands you'd type manually to move it to
`10.10.10.3/24` and persist the change with `save`.

> ⚠️ This is a recovery tool, not a continuous-state manager.
> `terraform apply` reconnects to `192.168.2.1` on every run and will
> short-circuit if the switch is already at the target IP.

## Layout

| File | Purpose |
| --- | --- |
| `versions.tf` | Terraform + provider pinning (`hashicorp/null`) |
| `variables.tf` | Inputs with validation |
| `main.tf` | `null_resource` with gated `local-exec` script |
| `outputs.tf` | Post-run SSH/web hints |
| `terraform.tfvars.example` | Copy → `terraform.tfvars` for local overrides |
| `.env.local.example` | Copy → `.env.local` for `TF_VAR_switch_password` |

## Prerequisites

- **Bash + sshpass** — easiest via WSL Ubuntu:
  ```bash
  sudo apt update && sudo apt install -y sshpass
  ```
- **Terraform ≥ 1.5** (OpenTofu ≥ 1.5 also works)
- Laptop NIC on the same subnet as the switch's **current** IP
  (`192.168.2.0/24` after a reset).

## Where to run `terraform apply`

You have two options:

**Option A — from WSL (recommended, zero config)**

```bash
cd /mnt/c/Users/Job/Documents/k8s-home-server/infrastructure/horaco-switch
export TF_VAR_switch_password='admin'
terraform init
terraform apply
```

The default interpreter (`/bin/sh` → `bash`) is used. Nothing to change.

**Option B — from PowerShell on Windows (requires WSL)**

Uncomment the `interpreter` line at the top of the provisioner in
`main.tf`:

```hcl
interpreter = ["wsl.exe", "-e", "bash", "-c"]
```

Then from PowerShell:

```powershell
$env:TF_VAR_switch_password = 'admin'
terraform init
terraform apply
```

## One-time manual step after a factory reset

SSH is **disabled** on a freshly reset switch. The script gates on SSH
port 22 being open, so you must enable it manually once:

1. Set laptop NIC to `192.168.2.100/24` (no gateway).
2. Browse to <http://192.168.2.1>, log in `admin` / `admin`.
3. **Security → Management Access → Management Service** → toggle
   **SSH** on → **Apply**.
4. Leave the IP alone — the script changes it (the web UI hangs if you
   try it there).

## Running the recovery

```bash
export TF_VAR_switch_password='admin'
terraform init
terraform apply
```

### Gates and behaviour

| Situation | What happens |
| --- | --- |
| Missing `sshpass` / `ssh` / `ping` | Errors before touching the switch. |
| `switch_host == switch_new_ip` | Errors immediately (variable sanity). |
| Already on `10.10.10.3` | Pings target, prints `skipping configuration`, exits 0. |
| On `192.168.2.1`, SSH enabled | Runs `configure` / `ip address` / `save`. |
| On `192.168.2.1`, SSH **disabled** | Gate 5 fails with a hint to enable SSH. |
| Neither IP reachable | Errors with a hint to check your NIC subnet. |
| SSH dies mid-run (exit 255) | Treated as expected; verification continues. |
| New IP never comes up | Gate 6 fails after 10s with a clear error. |

To force reconfiguration even if the switch already responds at the new IP:

```bash
terraform apply -var force_reconfigure=true
```

### Note on `terraform plan`

The plan will always show *1 resource to add* because of the
`timestamp()` trigger. That's intentional — the no-op behaviour lives in
the provisioner, not the plan graph. See
`data "external"` in git history if you later want plan-time accuracy.

## Why the odd SSH flags?

- `-oHostKeyAlgorithms=+ssh-rsa` — the firmware only offers legacy
  `ssh-rsa` host keys, which modern OpenSSH rejects by default.
- `-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null` — factory
  resets regenerate host keys, so we don't want `known_hosts` state
  poisoning the next recovery run.

## Cleanup after switching from `brennoo/hrui`

If you previously initialised the `brennoo/hrui` provider, run once after
pulling these files:

```bash
terraform init -upgrade
```

This drops stale lock entries and pulls `hashicorp/null`.