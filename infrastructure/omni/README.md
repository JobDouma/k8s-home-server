# Omni Service — GitOps Deployment

Omni (`ghcr.io/siderolabs/omni`) plus Garage (its etcd-backup S3 backend) run
as plain Docker Compose services directly on `ubuntu-server`'s host network —
**not** inside the Kubernetes cluster Omni manages. That's intentional: the
tool that bootstraps and manages your Talos/k8s cluster shouldn't itself
depend on that cluster being up.

This directory is the git source of truth. The actual running copy lives at
`/opt/omni` on the host and is synced from here by `upgrade.sh`.

## Step 0 — Rotate secrets before deploying (do this first)

Both of these were exposed in plaintext during troubleshooting and must be
treated as compromised:

1. **OIDC client secret** — In Authentik: **Applications → Providers → your
   Omni provider → regenerate the client secret**.
2. **Garage S3 backup key** — already rotated during setup:
   ```bash
   docker compose exec garage /garage key delete omni-etcd-backup-key
   docker compose exec garage /garage key create omni-etcd-backup-key
   docker compose exec garage /garage bucket allow omni-etcd-backups \
     --key omni-etcd-backup-key --read --write
   ```
3. Put both new values into `secret.yaml` (see below) before running `upgrade.sh`.

## What's tracked in git vs. what isn't

| Path | In git? | Why |
|---|---|---|
| `docker-compose.yml` | Yes | Service definitions (Omni + Garage) |
| `garage-config/garage.toml` | Yes | Garage config — contains `rpc_secret`/`admin_token`, generated once locally, never exposed externally. Treat as sensitive even though it's committed in this repo's threat model (private git, sops-protected repo) — do not copy this file elsewhere without the same protection. |
| `secret.yaml` | Yes (SOPS-encrypted) | OIDC client secret + Garage S3 access/secret key |
| `upgrade.sh` | Yes | Idempotent sync + upgrade script |
| `cluster-template.yaml` | **No** (gitignored) | Exported snapshot of `homelab-1`. **Never commit this** — every `omnictl cluster template export` embeds the current live SideroLink jointoken in plaintext (`apiUrl: ...?jointoken=...`), which is a working credential, not a config value. Regenerate locally when you need to inspect or diff it: `omnictl cluster template export -c homelab-1 -o cluster-template.yaml`. If you ever need `sync` for disaster recovery, export fresh rather than trusting an old copy. |
| `/opt/omni/omni.asc` | **No** | Omni's PGP identity key. Every enrolled Talos machine trusts this. Losing it means re-enrolling every node. |
| `/opt/omni/tls.crt` / `tls.key` | **No** | TLS serving cert/key for `omni.lan` |
| `/opt/omni/etcd/`, `/opt/omni/sqlite/` | **No** | Live Omni database — accounts, cluster registrations, machine state |
| `/mnt/truenas-backups/ubuntu-server/omni/garage-data`, `garage-meta` | **No** | Garage's own data, on the NFS share, outside git — this is Garage's storage, separate from what it stores *for* Omni |

The three host-only Omni items should already be covered by whatever you're
using under `~/secure-backups`. If they're not backed up yet, do that before
relying on this repo for disaster recovery — `upgrade.sh` refuses to start if
they're missing, on purpose.

## Authentication (Authentik OIDC)

Omni auth is OIDC against Authentik, provider/app slug `omni` (must match —
issuer URL is `https://auth.lan/application/o/omni/`).

Key flags on the `omni` command:
- `--auth-oidc-enabled=true`, `--auth-auth0-enabled=false`, `--auth-saml-enabled=false`
- `--auth-oidc-provider-url=https://auth.lan/application/o/omni/`
- `--auth-oidc-client-id=omni-homelab`
- `--auth-oidc-allow-unverified-email=true` — **required**. Authentik doesn't
  set `email_verified: true` for admin-created accounts by default; Omni
  rejects the JWT without this flag (`"invalid jwt": "email not verified"`).

In Authentik, the provider's **Authorization flow** must be an
`Authorization`-type flow (`default-provider-authorization-explicit-consent`
or `-implicit-consent`), **not** a generic Authentication flow — otherwise
login succeeds but Authentik has no OAuth redirect context to hand back to
Omni, and you get stuck on a generic "you can return to the application" page.

## Image versions

```yaml
omni:   ghcr.io/siderolabs/omni:v1.9.1
garage: dxflrs/garage:v2.3.0
```

**Never pin Omni by digest to a beta build.** An earlier accidental `:latest`
pull landed on `v1.9.0-beta.0`, which had an incomplete/broken frontend
bundle and had bumped the embedded etcd to a version (3.7.0) that no released
or planned Omni build actually ships — making that data directory a
permanent dead end. If you ever see hashed `.js` filenames failing to load
with MIME-type errors in the browser console, check the image tag first.

**On Garage's version**: sources on the current release conflict somewhat
(some show `v2.3.0`, older guides reference `v1.x`) — double check
`garagehq.deuxfleurs.fr/download` for the actual latest before Renovate
bumps this further, since it wasn't fully confirmed at time of writing.

## etcd backups (Garage)

Omni's built-in etcd backup only speaks the S3 API. **MinIO was the original
choice but its official image was archived/frozen in April 2026**, so this
uses Garage instead — lightweight, actively maintained, purpose-built for
single-node self-hosted use (unlike MinIO, designed for large clusters).

- Garage data: `/mnt/truenas-backups/ubuntu-server/omni/garage-data` +
  `garage-meta`, on the NFS share — deliberately not local disk (a local path
  dies with the host) and not git (binary data doesn't belong versioned).
- Bucket: `omni-etcd-backups`, single-node layout, zone `homelab`.
- **Path gotcha**: `garage.toml`'s `data_dir`/`metadata_dir` must be the
  **container-side** paths (`/var/lib/garage/...`), not the host NFS paths —
  the host paths only ever appear in `docker-compose.yml`'s `volumes:`
  mapping. Mixing these up produces a `garage-marker` error that looks like
  a permissions problem but isn't.

Trigger a manual backup any time:
```bash
cat <<EOF > /tmp/etcd-manual-backup.yaml
metadata:
  namespace: ephemeral
  type: EtcdManualBackups.omni.sidero.dev
  id: homelab-1
spec:
  backupat:
    seconds: $(date +%s)
    nanos: 0
EOF
omnictl apply -f /tmp/etcd-manual-backup.yaml
omnictl get etcdbackupstatus homelab-1 -o yaml
```

## cluster-template.yaml — how to use this file safely

Regenerate it any time from the live cluster:
```bash
omnictl cluster template export -c homelab-1 -o cluster-template.yaml
```

**Safe operations, any time:**
- `omnictl cluster template diff -f cluster-template.yaml` — read-only, no changes.
- Re-running `export` after UI changes, to keep this file current.

**Not safe to run casually:**
- `omnictl cluster template sync -f cluster-template.yaml` — live reconciliation.
  If the file differs from actual cluster state, `sync` will change the
  running cluster to match it (add/remove machines, trigger upgrades). Only
  run `sync` when you specifically intend to change the cluster via this
  file, and always `diff` first.

**Single control-plane node caveat:** `homelab-1` runs with exactly 1
control-plane node — zero etcd quorum tolerance. Worth adding a second when
practical.

## First-time deploy / Day-2 updates

```bash
# Fill in secrets (see Step 0)
sops infrastructure/omni/secret.yaml

git add infrastructure/omni/
git commit -m "omni: Garage etcd backups (replacing archived MinIO), rotated secrets"
git push

cd infrastructure/omni
chmod +x upgrade.sh
./upgrade.sh
```

`upgrade.sh` decrypts all three secrets, writes `/opt/omni/.env` (git-ignored,
host-only), syncs `docker-compose.yml` and `garage-config/garage.toml` into
`/opt/omni`, and runs `docker compose up -d`. Idempotent — safe to re-run any
time, including after a Renovate PR bumps an image tag.

Verify:
```bash
docker logs -f omni
docker logs -f omni-backup-garage
docker compose exec garage /garage status
```

## Disaster recovery — if Omni's database is lost again

1. Restore `omni.asc`, `tls.crt`, `tls.key` into `/opt/omni/` from `secure-backups`.
2. Confirm the NFS share is mounted and `garage-data`/`garage-meta` still
   have content (Garage's own data — layout, keys, bucket — lives there and
   survives an Omni wipe independently).
3. `./upgrade.sh` — brings both services up fresh.
4. Restore `~/.talos/config` (talosconfig) from `secure-backups` or
   `secrets/talosconfig.secret.yaml` if tracked.
5. Point the Talos endpoint at a **control-plane** node specifically (workers
   cannot forward Talos API requests to other nodes):
   ```bash
   talosctl --talosconfig ~/.talos/config config endpoint <control-plane-ip>
   ```
6. Re-import:
   ```bash
   omnictl cluster import --talosconfig ~/.talos/config \
     --nodes <cp-ip>,<worker-ip> --force --skip-health-check
   ```
   (`--skip-health-check` is safe if `kubectl get nodes` independently shows
   the cluster healthy — the built-in check reaches for a SideroLink tunnel
   address that doesn't exist yet pre-import, so it always times out.)
7. Rotate PKI immediately (imported clusters are tainted — old
   talosconfig/kubeconfig copies retain valid access until rotated):
   ```bash
   omnictl cluster -n homelab-1 secret rotate talos-ca
   omnictl cluster -n homelab-1 secret rotate kubernetes-ca
   ```
8. Re-export the template and commit it.

## Why the `extra_hosts` line exists

`network_mode: host` makes the container share the host's network *stack*,
but Docker still writes the container a **separate `/etc/hosts`** — it does
not inherit the host's. The OIDC token exchange happens server-side, inside
the container, so it needs to resolve `auth.lan` itself. If your DNS resolver
(Blocky, `192.168.2.53`) is ever down, resolution fails even though the
browser-side login appeared to succeed. `extra_hosts` pins it so token
exchange never depends on Blocky's uptime.