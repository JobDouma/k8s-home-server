# Omni Service — GitOps Deployment

Omni (`ghcr.io/siderolabs/omni`) runs as a plain Docker Compose service directly
on `ubuntu-server`'s host network — **not** inside the Kubernetes cluster it
manages. That's intentional: the tool that bootstraps and manages your Talos/
k8s cluster shouldn't itself depend on that cluster being up.

This directory is the git source of truth for that service. The actual running
copy lives at `/opt/omni` on the host and is synced from here by `upgrade.sh`.

## Step 0 — Rotate the OIDC client secret (do this first)

The current Omni OIDC client secret was pasted in plaintext during
troubleshooting and should be treated as compromised:

1. In Authentik: **Applications → Providers → omni-oauth2 → ⋮ → ... regenerate
   the client secret** (or delete/recreate the OAuth2 provider).
2. Use the *new* secret in Step 2 below.
3. Old sessions/tokens issued with the old secret will stop working — expected.

## What's tracked in git vs. what isn't

| Path | In git? | Why |
|---|---|---|
| `docker-compose.yml` | Yes | Service definition |
| `secret.yaml` | Yes (SOPS-encrypted) | Only the OIDC client secret |
| `upgrade.sh` | Yes | Idempotent sync + upgrade script |
| `/opt/omni/omni.asc` | **No** | Omni's PGP identity key. This is what every enrolled Talos machine trusts. Losing it means re-enrolling every node. |
| `/opt/omni/tls.crt` / `tls.key` | **No** | TLS serving cert/key for `omni.lan` |
| `/opt/omni/etcd/`, `/opt/omni/sqlite/` | **No** | Live cluster state/database |

The four host-only items above should already be covered by whatever you're
using under `~/secure-backups`. If they're not backed up yet, do that before
relying on this repo for disaster recovery — `upgrade.sh` will refuse to start
if they're missing, on purpose.

## Versioning: how this differs from the code-server pattern

If you're used to the `version.yaml` + `upgrade.sh` pattern from `infrastructure/vs-code/` for code-server, note that Omni is set up differently on purpose:

code-server is a downloaded `.deb`, installed via `dpkg`, with no registry or
manifest to pin a version against — so `version.yaml` exists purely to give
Renovate *something* to bump, and `upgrade.sh` does the heavy lifting
(checksum, download, install).

Omni is a container. The version pin already has a natural home — the
`image:` tag in `docker-compose.yml` — and Renovate's `docker-compose`
manager (enabled by default in standard presets) watches `image:` lines
directly and opens PRs bumping them, the same way it would for any other
Docker Compose service in this repo. So there's no `version.yaml` for Omni;
the tag in `docker-compose.yml` *is* the version source of truth. One fewer
file to keep in sync, and Docker's image digests already give you integrity
verification for free (no separate checksum step needed, unlike the raw
`.deb`).

`upgrade.sh` mirrors the *spirit* of code-server's script though: it compares
the image tag already running to the tag pinned in `docker-compose.yml` and
skips the pull/restart if they already match, so it's safe to re-run after
every Renovate merge, or for unrelated reasons (e.g. just rotating the OIDC
secret) without forcing an unnecessary container restart.

## EULA acceptance (added in v1.7.1)

Omni added a mandatory EULA acceptance step in v1.7.1, with `--eula-accept-name`
and `--eula-accept-email` flags as the way to accept it non-interactively.
Without them, an unattended container start can get stuck. These are already
in `docker-compose.yml` — **just replace `CHANGE_ME` with your actual name
before running `upgrade.sh` for the first time on this config.**



## First-time deploy on a host that already has the key material

If `/opt/omni/{omni.asc,tls.crt,tls.key}` already exist (e.g. this is just
moving the *config* into git for the first time, like today):

```bash
# 1. Fill in and encrypt the secret
sops infrastructure/omni/secret.yaml
# replace REPLACE_ME_BEFORE_ENCRYPTING with the new client secret from Step 0,
# save and quit — sops encrypts the stringData block automatically.

# 2. Commit
git add infrastructure/omni/
git commit -m "Track Omni docker-compose config in git, fix auth.lan DNS"
git push

# 3. Deploy
cd infrastructure/omni
chmod +x upgrade.sh
./upgrade.sh
```

`upgrade.sh` decrypts the secret, writes `/opt/omni/.env` (git-ignored, host-only),
copies `docker-compose.yml` into `/opt/omni`, and runs `docker compose up -d`.

Verify:

```bash
docker logs -f omni
docker exec omni cat /etc/hosts | grep auth.lan   # should show 192.168.2.100
```

Then log into Omni and confirm the Authentik flow completes without the
`dial tcp: lookup auth.lan` error.

## Day-2: updating the config

Any time you change `docker-compose.yml` — most commonly, merging a Renovate
PR that bumped the `image:` tag, but also any flag/port/volume change:

```bash
git pull
cd infrastructure/omni
./upgrade.sh
```

Idempotent — safe to re-run any time. It skips the image pull entirely if
the tag hasn't changed since the last run.

## Rotating the secret later

```bash
sops infrastructure/omni/secret.yaml   # edit the value, save
git add infrastructure/omni/secret.yaml
git commit -m "Rotate Omni OIDC client secret"
git push
./upgrade.sh
```

Don't forget to regenerate the matching secret in Authentik first, same as
Step 0.

## Disaster recovery (new/replacement host)

1. Install Docker + Compose plugin, and `sops` with access to the repo's age
   key (`~/.config/sops/age/keys.txt`).
2. Restore `omni.asc`, `tls.crt`, `tls.key`, `etcd/`, and `sqlite/` from
   `secure-backups` into `/opt/omni/`.
3. Restore `/usr/local/share/ca-certificates/homelab-ca.crt` and run
   `update-ca-certificates` if needed.
4. Clone this repo, `cd infrastructure/omni && ./upgrade.sh`.

## Why the `extra_hosts` line exists

`network_mode: host` makes the container share the host's network *stack*,
but Docker still writes the container a **separate `/etc/hosts`** — it does
not inherit the host's. The OIDC token exchange
(`POST https://auth.lan/application/o/token/`) happens server-side, inside
the container, so it needs to resolve `auth.lan` itself. If your DNS resolver
(Blocky, `192.168.2.53`) is ever down, resolution falls through to the public
fallback resolvers and `auth.lan` fails to resolve (`NXDOMAIN`/`no such host`),
even though the browser-side login appeared to succeed. The `extra_hosts`
entry pins it so token exchange never depends on Blocky's uptime.