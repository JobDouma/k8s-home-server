#!/usr/bin/env bash
set -euo pipefail

# Deploys AND upgrades the Omni + Garage docker-compose stack on THIS host
# from the git-tracked config in this directory. Safe to re-run any time
# (idempotent): it compares the image tags already running against the tags
# pinned in docker-compose.yml and only pulls/restarts what changed.
#
# Renovate bumps image tags in docker-compose.yml directly (no separate
# version.yaml for container deployments - the tag IS the version source).
# Run this after merging a Renovate PR that bumps one, same as you'd run
# code-server's upgrade.sh after a version.yaml bump.
#
# /opt/omni is root-owned (Omni's container runs as root, no user namespace
# remap, so everything it manages on the host - etcd/, sqlite/ - ends up
# root-owned too). This script uses sudo for the specific writes that need
# it, then hands file ownership back to you so `docker compose` (running as
# your user, via the docker group) can still read what it needs.
#
# Garage's data lives on the NFS backups share, not under /opt/omni - see
# README.md. This script does not create that path; it must already exist
# (it's shared, persistent infrastructure, not something to recreate blindly
# on every deploy).
#
# Run on ubuntu-server, as a user with access to the sops age key
# (~/.config/sops/age/keys.txt) and sudo rights.
#
# Usage:
#   ./upgrade.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/opt/omni"
SECRET_FILE="${REPO_DIR}/secret.yaml"
COMPOSE_FILE="${REPO_DIR}/docker-compose.yml"
GARAGE_TOML_SOPS="${REPO_DIR}/garage-config/garage.config.sops.yaml"
GARAGE_DATA_NFS="/mnt/truenas-backups/ubuntu-server/omni/garage-data"
GARAGE_META_NFS="/mnt/truenas-backups/ubuntu-server/omni/garage-meta"
RUN_USER="$(id -un)"
RUN_GROUP="$(id -gn)"

command -v sops >/dev/null || { echo "ERROR: sops not found on PATH" >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker not found on PATH" >&2; exit 1; }

for f in "${DEPLOY_DIR}/omni.asc" "${DEPLOY_DIR}/tls.crt" "${DEPLOY_DIR}/tls.key"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f — restore it from secure-backups before deploying. See README.md (Disaster Recovery)." >&2; exit 1; }
done
sudo mkdir -p "${DEPLOY_DIR}/etcd" "${DEPLOY_DIR}/sqlite"

for d in "$GARAGE_DATA_NFS" "$GARAGE_META_NFS"; do
  [[ -d "$d" ]] || { echo "ERROR: $d does not exist — NFS share not mounted, or Garage was never bootstrapped. See README.md." >&2; exit 1; }
done

echo "==> Decrypting secrets"

DECRYPTED_SECRET="$(sops -d "$SECRET_FILE")"

OMNI_OIDC_CLIENT_SECRET="$(echo "$DECRYPTED_SECRET" | yq -r '.stringData.OMNI_OIDC_CLIENT_SECRET')"
OMNI_ETCD_BACKUP_S3_ACCESS_KEY="$(echo "$DECRYPTED_SECRET" | yq -r '.stringData.OMNI_ETCD_BACKUP_S3_ACCESS_KEY')"
OMNI_ETCD_BACKUP_S3_SECRET_KEY="$(echo "$DECRYPTED_SECRET" | yq -r '.stringData.OMNI_ETCD_BACKUP_S3_SECRET_KEY')"

for pair in "OMNI_OIDC_CLIENT_SECRET:$OMNI_OIDC_CLIENT_SECRET" \
            "OMNI_ETCD_BACKUP_S3_ACCESS_KEY:$OMNI_ETCD_BACKUP_S3_ACCESS_KEY" \
            "OMNI_ETCD_BACKUP_S3_SECRET_KEY:$OMNI_ETCD_BACKUP_S3_SECRET_KEY"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if [[ -z "$value" || "$value" == REPLACE_ME_* ]]; then
    echo "ERROR: ${name} in secret.yaml is not filled in yet. Aborting." >&2
    exit 1
  fi
done

echo "==> Checking current vs. target versions"
TARGET_IMAGES="$(OMNI_OIDC_CLIENT_SECRET="$OMNI_OIDC_CLIENT_SECRET" \
  OMNI_ETCD_BACKUP_S3_ACCESS_KEY="$OMNI_ETCD_BACKUP_S3_ACCESS_KEY" \
  OMNI_ETCD_BACKUP_S3_SECRET_KEY="$OMNI_ETCD_BACKUP_S3_SECRET_KEY" \
  docker compose -f "$COMPOSE_FILE" config --images)"
CURRENT_OMNI_IMAGE="$(docker inspect --format '{{.Config.Image}}' omni 2>/dev/null || true)"
CURRENT_GARAGE_IMAGE="$(docker inspect --format '{{.Config.Image}}' omni-backup-garage 2>/dev/null || true)"

echo "    Target images:"
echo "$TARGET_IMAGES" | sed 's/^/      /'
echo "    Currently running: omni=${CURRENT_OMNI_IMAGE:-<none>}  garage=${CURRENT_GARAGE_IMAGE:-<none>}"

echo "==> Writing ${DEPLOY_DIR}/.env (atomic)"

TMP_ENV="$(mktemp)"

cat > "$TMP_ENV" <<EOF
OMNI_OIDC_CLIENT_SECRET=${OMNI_OIDC_CLIENT_SECRET}
OMNI_ETCD_BACKUP_S3_ACCESS_KEY=${OMNI_ETCD_BACKUP_S3_ACCESS_KEY}
OMNI_ETCD_BACKUP_S3_SECRET_KEY=${OMNI_ETCD_BACKUP_S3_SECRET_KEY}
EOF

sudo mv "$TMP_ENV" "${DEPLOY_DIR}/.env"
sudo chown "${RUN_USER}:${RUN_GROUP}" "${DEPLOY_DIR}/.env"
sudo chmod 600 "${DEPLOY_DIR}/.env"

echo "==> Syncing docker-compose.yml and garage-config/ to ${DEPLOY_DIR}"
sudo cp "$COMPOSE_FILE" "${DEPLOY_DIR}/docker-compose.yml"
sudo mkdir -p "${DEPLOY_DIR}/garage-config"
echo "==> Decrypting Garage configuration"

DECRYPTED_GARAGE="$(sops -d "$GARAGE_TOML_SOPS")"

echo "$DECRYPTED_GARAGE" \
    | yq -r '.stringData["garage.toml"]' \
    | sudo tee "${DEPLOY_DIR}/garage-config/garage.toml" >/dev/null

sudo chown "${RUN_USER}:${RUN_GROUP}" "${DEPLOY_DIR}/garage-config/garage.toml"
sudo chmod 600 "${DEPLOY_DIR}/garage-config/garage.toml"

sudo chown -R "${RUN_USER}:${RUN_GROUP}" "${DEPLOY_DIR}/docker-compose.yml" "${DEPLOY_DIR}/garage-config"

cd "$DEPLOY_DIR"
echo "==> Validating docker compose configuration"

docker compose \
    --env-file .env \
    config >/dev/null
docker compose up -d --pull always
echo "==> Service status"
docker compose ps

echo "==> Done."
echo "    omni:   $(docker inspect --format '{{.Config.Image}}' omni)"
echo "    garage: $(docker inspect --format '{{.Config.Image}}' omni-backup-garage)"
echo "    Logs:   docker logs -f omni"
echo "            docker logs -f omni-backup-garage"
echo "    Verify: sudo cat \"\$(docker inspect --format '{{.HostsPath}}' omni)\" | grep auth.lan"
echo "            (the omni image has no shell/cat - docker exec won't work)"
echo "            docker compose exec garage /garage status"