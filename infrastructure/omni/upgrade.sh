#!/usr/bin/env bash
set -euo pipefail

# Deploys AND upgrades the Omni docker-compose service on THIS host from the
# git-tracked config in this directory. Safe to re-run any time (idempotent):
# it compares the image tag already running against the tag pinned in
# docker-compose.yml and only pulls/restarts if they differ.
#
# Renovate bumps the image tag in docker-compose.yml directly (no separate
# version.yaml for container deployments - the tag IS the version source).
# Run this after merging a Renovate PR that bumps it, same as you'd run
# code-server's upgrade.sh after a version.yaml bump.
#
# /opt/omni is root-owned (Omni's container runs as root, no user namespace
# remap, so everything it manages on the host - etcd/, sqlite/ - ends up
# root-owned too). This script uses sudo for the specific writes that need
# it, then hands file ownership back to you so `docker compose` (running as
# your user, via the docker group) can still read what it needs.
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

echo "==> Checking current vs. target version"
TARGET_IMAGE="$(OMNI_OIDC_CLIENT_SECRET="$OMNI_OIDC_CLIENT_SECRET" docker compose -f "$COMPOSE_FILE" config --images)"
CURRENT_IMAGE="$(docker inspect --format '{{.Config.Image}}' omni 2>/dev/null || true)"

SKIP_PULL=false
if [[ -z "$CURRENT_IMAGE" ]]; then
  echo "    No existing omni container found — first deploy of ${TARGET_IMAGE}"
elif [[ "$CURRENT_IMAGE" == "$TARGET_IMAGE" ]]; then
  echo "    Already running ${TARGET_IMAGE} — skipping image pull"
  SKIP_PULL=true
else
  echo "    Upgrading: ${CURRENT_IMAGE} -> ${TARGET_IMAGE}"
fi

echo "==> Writing ${DEPLOY_DIR}/.env (not committed to git)"
printf 'OMNI_OIDC_CLIENT_SECRET=%s\n' "$OMNI_OIDC_CLIENT_SECRET" | sudo tee "${DEPLOY_DIR}/.env" >/dev/null
sudo chown "${RUN_USER}:${RUN_GROUP}" "${DEPLOY_DIR}/.env"
sudo chmod 600 "${DEPLOY_DIR}/.env"

echo "==> Syncing docker-compose.yml to ${DEPLOY_DIR}"
sudo cp "$COMPOSE_FILE" "${DEPLOY_DIR}/docker-compose.yml"
sudo chown "${RUN_USER}:${RUN_GROUP}" "${DEPLOY_DIR}/docker-compose.yml"

cd "$DEPLOY_DIR"
if [[ "$SKIP_PULL" == "false" ]]; then
  echo "==> Pulling ${TARGET_IMAGE}"
  docker compose pull
fi

echo "==> Reconciling container state"
docker compose up -d

echo "==> Done. Now running: $(docker inspect --format '{{.Config.Image}}' omni)"
echo "    Logs:   docker logs -f omni"
echo "    Verify: sudo cat \"\$(docker inspect --format '{{.HostsPath}}' omni)\" | grep auth.lan"
echo "            (the omni image has no shell/cat - docker exec won't work)"