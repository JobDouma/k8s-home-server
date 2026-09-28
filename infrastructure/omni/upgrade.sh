#!/usr/bin/env bash
set -euo pipefail

# Deploys AND upgrades the Omni + Garage + Caddy docker-compose stack on THIS
# host from the git-tracked config in this directory. Safe to re-run any time
# (idempotent): compares the image tags already running against the tags
# pinned in docker-compose.yml and only pulls/restarts what changed.
#
# Renovate bumps image tags in docker-compose.yml directly (no separate
# version.yaml for container deployments - the tag IS the version source).
# Run this after merging a Renovate PR that bumps one.
#
# /opt/omni is root-owned (Omni's container runs as root, no user namespace
# remap, so everything it manages on the host - etcd/, sqlite/ - ends up
# root-owned too). This script uses sudo for the specific writes that need
# it, then hands file ownership back to you so `docker compose` (running as
# your user, via the docker group) can still read what it needs.
#
# Garage's metadata dir (garage-meta) lives LOCALLY under /opt/omni, not on
# NFS - LMDB (Garage's metadata engine) memory-maps its database and needs
# reliable file locking + coherent page cache, which NFS doesn't reliably
# provide. Only Garage's object DATA lives on the NFS backups share.
#
# The NFS data path must already exist and be an ACTUAL mount (shared,
# persistent infrastructure, not something to recreate blindly on every
# deploy - see the mountpoint check below).
#
# OIDC is provided by the Authentik docker stack in
# ../authentik-docker/. The client secret is read from that directory's
# SOPS-encrypted secret.yaml (key: OMNI_CLIENT_SECRET) so the two stacks
# stay in sync. Caddy terminates TLS on :443 for both omni.lan and auth.lan;
# Omni itself binds to :8443 behind the proxy.
#
# Caddyfile and certs/ are mounted into the container, so editing them on
# the host does NOT trigger a recreate. This script hashes the Caddyfile +
# certs after syncing and reloads Caddy in-place when they change.
#
# Run on ubuntu-server, as a user with access to the sops age key
# (~/.config/sops/age/keys.txt) and sudo rights.
#
# Usage:
#   ./upgrade.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/opt/omni"
COMPOSE_FILE="${REPO_DIR}/docker-compose.yml"
CADDYFILE="${REPO_DIR}/Caddyfile"
CERTS_SRC="${REPO_DIR}/certs"
GARAGE_TOML_SOPS="${REPO_DIR}/garage-config/garage.config.sops.yaml"
AUTHENTIK_SECRET="${REPO_DIR}/../authentik-docker/secret.yaml"
GARAGE_META_LOCAL="${DEPLOY_DIR}/garage-meta"
NFS_MOUNT_ROOT="/mnt/truenas-backups"
GARAGE_DATA_NFS="/mnt/truenas-backups/ubuntu-server/omni/garage-data"
CADDY_HASH_FILE="${DEPLOY_DIR}/.caddy-inputs.sha256"
RUN_USER="$(id -un)"
RUN_GROUP="$(id -gn)"

command -v sops   >/dev/null || { echo "ERROR: sops not found on PATH"   >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker not found on PATH" >&2; exit 1; }
command -v yq     >/dev/null || { echo "ERROR: yq not found on PATH"     >&2; exit 1; }

# --- Preflight ------------------------------------------------------------

for f in "${DEPLOY_DIR}/omni.asc" "${DEPLOY_DIR}/tls.crt" "${DEPLOY_DIR}/tls.key"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f — restore it from secure-backups before deploying. See README.md (Disaster Recovery)." >&2; exit 1; }
done

[[ -f "$CADDYFILE"  ]] || { echo "ERROR: missing $CADDYFILE — Caddy needs it to serve :443." >&2; exit 1; }
[[ -d "$CERTS_SRC"  ]] || { echo "ERROR: missing $CERTS_SRC/ — see README (TLS). Expected omni.lan.crt/.key and auth.lan.crt/.key." >&2; exit 1; }
for pair in omni.lan auth.lan; do
  for ext in crt key; do
    [[ -f "${CERTS_SRC}/${pair}.${ext}" ]] || {
      echo "ERROR: missing ${CERTS_SRC}/${pair}.${ext}" >&2; exit 1; }
  done
done

[[ -f "$AUTHENTIK_SECRET" ]] || {
  echo "ERROR: missing $AUTHENTIK_SECRET — needed for OMNI_CLIENT_SECRET." >&2; exit 1; }

sudo mkdir -p "${DEPLOY_DIR}/etcd" "${DEPLOY_DIR}/sqlite" "${GARAGE_META_LOCAL}"

# Real mount check, not just "directory exists". If the NFS share is
# unmounted, the mountpoint directory still exists locally (empty) and a
# plain `[[ -d ... ]]` check would pass silently - Garage would then happily
# write backup blobs to the VM's local root disk instead of the NFS share,
# filling it up. Fail loudly instead.
mountpoint -q "$NFS_MOUNT_ROOT" || { echo "ERROR: ${NFS_MOUNT_ROOT} is NOT an active mount — NFS share not mounted. Check 'systemctl status mnt-truenas\\x2dbackups.mount'." >&2; exit 1; }
[[ -d "$GARAGE_DATA_NFS" ]] || { echo "ERROR: ${GARAGE_DATA_NFS} does not exist under the NFS mount — Garage was never bootstrapped there. See README.md." >&2; exit 1; }

TEST_FILE="${GARAGE_DATA_NFS}/.upgrade-sh-write-test"
( touch "$TEST_FILE" && rm -f "$TEST_FILE" ) 2>/dev/null || { echo "ERROR: ${GARAGE_DATA_NFS} is mounted but not writable by ${RUN_USER}. Check NFS export permissions." >&2; exit 1; }

# --- Secrets --------------------------------------------------------------

echo "==> Reading OMNI_CLIENT_SECRET from ${AUTHENTIK_SECRET}"
OMNI_CLIENT_SECRET="$(sops -d "$AUTHENTIK_SECRET" | yq -r '.stringData.OMNI_CLIENT_SECRET')"
if [[ -z "$OMNI_CLIENT_SECRET" || "$OMNI_CLIENT_SECRET" == "null" || "$OMNI_CLIENT_SECRET" == REPLACE_ME_* ]]; then
  echo "ERROR: OMNI_CLIENT_SECRET is empty in ${AUTHENTIK_SECRET}. Fill it and re-encrypt." >&2
  exit 1
fi

echo "==> Writing ${DEPLOY_DIR}/.env (atomic)"
TMP_ENV="$(mktemp)"
cat > "$TMP_ENV" <<EOF
OMNI_CLIENT_SECRET=${OMNI_CLIENT_SECRET}
EOF
sudo mv "$TMP_ENV" "${DEPLOY_DIR}/.env"
sudo chown "${RUN_USER}:${RUN_GROUP}" "${DEPLOY_DIR}/.env"
sudo chmod 600 "${DEPLOY_DIR}/.env"

# --- Version comparison ---------------------------------------------------

echo "==> Checking current vs. target versions"
TARGET_IMAGES="$(docker compose -f "$COMPOSE_FILE" --env-file "${DEPLOY_DIR}/.env" config --images)"
CURRENT_OMNI_IMAGE="$(docker inspect --format '{{.Config.Image}}' omni 2>/dev/null || true)"
CURRENT_GARAGE_IMAGE="$(docker inspect --format '{{.Config.Image}}' omni-backup-garage 2>/dev/null || true)"
CURRENT_CADDY_IMAGE="$(docker inspect --format '{{.Config.Image}}' caddy 2>/dev/null || true)"

echo "    Target images:"
echo "$TARGET_IMAGES" | sed 's/^/      /'
echo "    Currently running:"
echo "      omni=${CURRENT_OMNI_IMAGE:-<none>}"
echo "      garage=${CURRENT_GARAGE_IMAGE:-<none>}"
echo "      caddy=${CURRENT_CADDY_IMAGE:-<none>}"

# --- Sync compose, Caddyfile, certs, garage config ------------------------

echo "==> Syncing docker-compose.yml, Caddyfile, certs/, garage-config/ to ${DEPLOY_DIR}"
sudo cp "$COMPOSE_FILE" "${DEPLOY_DIR}/docker-compose.yml"
sudo cp "$CADDYFILE"    "${DEPLOY_DIR}/Caddyfile"

sudo mkdir -p "${DEPLOY_DIR}/certs"
sudo cp -a "${CERTS_SRC}/." "${DEPLOY_DIR}/certs/"

sudo mkdir -p "${DEPLOY_DIR}/garage-config"
echo "==> Decrypting Garage configuration"
DECRYPTED_GARAGE="$(sops -d "$GARAGE_TOML_SOPS")"
echo "$DECRYPTED_GARAGE" \
    | yq -r '.stringData["garage.toml"]' \
    | sudo tee "${DEPLOY_DIR}/garage-config/garage.toml" >/dev/null

sudo chown -R "${RUN_USER}:${RUN_GROUP}" \
    "${DEPLOY_DIR}/docker-compose.yml" \
    "${DEPLOY_DIR}/Caddyfile" \
    "${DEPLOY_DIR}/certs" \
    "${DEPLOY_DIR}/garage-config"

# Certs contain private keys; keep them owner-only.
sudo chmod 600 "${DEPLOY_DIR}/certs/"*.key
sudo chmod 644 "${DEPLOY_DIR}/certs/"*.crt
sudo chmod 600 "${DEPLOY_DIR}/garage-config/garage.toml"

# --- Bring up -------------------------------------------------------------

cd "$DEPLOY_DIR"

echo "==> Validating docker compose configuration"
docker compose --env-file .env config >/dev/null

echo "==> Pulling and (re)starting"
docker compose --env-file .env up -d --pull always --remove-orphans

# Compose only recreates a container when the compose config changes, so
# edits to bind-mounted files (Caddyfile, certs) are silently ignored. Detect
# them by hashing the inputs and reload Caddy in-place when they change.
NEW_HASH="$(cat "${DEPLOY_DIR}/Caddyfile" "${DEPLOY_DIR}/certs/"*.crt "${DEPLOY_DIR}/certs/"*.key | sha256sum | awk '{print $1}')"
OLD_HASH="$(cat "$CADDY_HASH_FILE" 2>/dev/null || echo '')"

if [[ "$NEW_HASH" != "$OLD_HASH" ]]; then
  echo "==> Caddy inputs changed, reloading caddy"
  if docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile 2>/dev/null; then
    echo "    reload ok"
  else
    echo "    reload failed (admin API disabled or syntax error), restarting caddy"
    docker compose --env-file .env restart caddy
  fi
  echo "$NEW_HASH" | sudo tee "$CADDY_HASH_FILE" >/dev/null
  sudo chown "${RUN_USER}:${RUN_GROUP}" "$CADDY_HASH_FILE"
fi

echo "==> Service status"
docker compose ps

echo "==> Memory limits in effect (host has 4GB total - keep an eye on this)"
docker inspect --format '    {{.Name}}: limit={{.HostConfig.Memory}} bytes' \
    omni omni-backup-garage caddy 2>/dev/null || true

# --- Post-up checks -------------------------------------------------------

echo "==> Verifying reverse proxy responds"
for host in omni.lan auth.lan; do
  code="$(curl -sk -o /dev/null -w '%{http_code}' \
      --resolve "${host}:443:127.0.0.1" "https://${host}/" || true)"
  echo "    https://${host}/ -> ${code:-<no response>}"
done

echo "==> Done."
echo "    omni:   $(docker inspect --format '{{.Config.Image}}' omni 2>/dev/null || echo '<not running>')"
echo "    garage: $(docker inspect --format '{{.Config.Image}}' omni-backup-garage 2>/dev/null || echo '<not running>')"
echo "    caddy:  $(docker inspect --format '{{.Config.Image}}' caddy 2>/dev/null || echo '<not running>')"
echo "    Logs:   docker logs -f omni"
echo "            docker logs -f omni-backup-garage"
echo "            docker logs -f caddy"
echo "    Verify: docker compose exec garage /garage status"
echo "            curl -sk https://127.0.0.1/ -H 'Host: omni.lan' -o /dev/null -w '%{http_code}\\n'"
echo "            curl -sk https://127.0.0.1/ -H 'Host: auth.lan' -o /dev/null -w '%{http_code}\\n'"
echo "    Watch:  docker stats omni omni-backup-garage caddy"