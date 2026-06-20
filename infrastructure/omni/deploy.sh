#!/usr/bin/env bash
set -euo pipefail

# Deploys/updates the Omni docker-compose service on THIS host from the
# git-tracked config in this directory.
#
# /opt/omni is root-owned (Omni's container runs as root with no user
# namespace remap, so everything it manages on the host - etcd/, sqlite/ -
# ends up root-owned too). This script uses sudo for the specific writes
# that need it, then hands file ownership back to you so `docker compose`
# (running as your user, via the docker group) can still read what it needs.
#
# Run on ubuntu-server, as a user with access to the sops age key
# (~/.config/sops/age/keys.txt) and sudo rights.
#
# Usage:
#   ./deploy.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/opt/omni"
SECRET_FILE="${REPO_DIR}/secret.yaml"
COMPOSE_FILE="${REPO_DIR}/docker-compose.yml"
RUN_USER="$(id -un)"
RUN_GROUP="$(id -gn)"

command -v sops >/dev/null || { echo "ERROR: sops not found on PATH" >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker not found on PATH" >&2; exit 1; }

for f in "${DEPLOY_DIR}/omni.asc" "${DEPLOY_DIR}/tls.crt" "${DEPLOY_DIR}/tls.key"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f — restore it from secure-backups before deploying. See README.md (Disaster Recovery)." >&2; exit 1; }
done
sudo mkdir -p "${DEPLOY_DIR}/etcd" "${DEPLOY_DIR}/sqlite"

echo "==> Decrypting OIDC client secret"
OMNI_OIDC_CLIENT_SECRET="$(sops -d --extract '["stringData"]["OMNI_OIDC_CLIENT_SECRET"]' "$SECRET_FILE")"

if [[ -z "$OMNI_OIDC_CLIENT_SECRET" || "$OMNI_OIDC_CLIENT_SECRET" == "REPLACE_ME_BEFORE_ENCRYPTING" ]]; then
  echo "ERROR: secret.yaml is not filled in / not encrypted yet. Aborting." >&2
  exit 1
fi

echo "==> Writing ${DEPLOY_DIR}/.env (not committed to git)"
printf 'OMNI_OIDC_CLIENT_SECRET=%s\n' "$OMNI_OIDC_CLIENT_SECRET" | sudo tee "${DEPLOY_DIR}/.env" >/dev/null
sudo chown "${RUN_USER}:${RUN_GROUP}" "${DEPLOY_DIR}/.env"
sudo chmod 600 "${DEPLOY_DIR}/.env"

echo "==> Syncing docker-compose.yml to ${DEPLOY_DIR}"
sudo cp "$COMPOSE_FILE" "${DEPLOY_DIR}/docker-compose.yml"
sudo chown "${RUN_USER}:${RUN_GROUP}" "${DEPLOY_DIR}/docker-compose.yml"

echo "==> Pulling latest image and starting Omni"
cd "$DEPLOY_DIR"
docker compose pull
docker compose up -d

echo "==> Done."
echo "    Logs:   docker logs -f omni"
echo "    Verify: docker exec omni cat /etc/hosts | grep auth.lan"