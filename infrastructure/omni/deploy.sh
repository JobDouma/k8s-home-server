#!/usr/bin/env bash
set -euo pipefail

# Deploys/updates the Omni docker-compose service on THIS host from the
# git-tracked config in this directory.
#
# Run on ubuntu-server, as a user with access to the sops age key
# (~/.config/sops/age/keys.txt) and with passwordless (or interactive)
# sudo for writing into /opt/omni.
#
# Usage:
#   ./deploy.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/opt/omni"
SECRET_FILE="${REPO_DIR}/secret.yaml"
COMPOSE_FILE="${REPO_DIR}/docker-compose.yml"

command -v sops >/dev/null || { echo "ERROR: sops not found on PATH" >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker not found on PATH" >&2; exit 1; }

for f in "${DEPLOY_DIR}/omni.asc" "${DEPLOY_DIR}/tls.crt" "${DEPLOY_DIR}/tls.key"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f — restore it from secure-backups before deploying. See README.md (Disaster Recovery)." >&2; exit 1; }
done
mkdir -p "${DEPLOY_DIR}/etcd" "${DEPLOY_DIR}/sqlite"

echo "==> Decrypting OIDC client secret"
OMNI_OIDC_CLIENT_SECRET="$(sops -d --extract '["stringData"]["OMNI_OIDC_CLIENT_SECRET"]' "$SECRET_FILE")"

if [[ -z "$OMNI_OIDC_CLIENT_SECRET" || "$OMNI_OIDC_CLIENT_SECRET" == "REPLACE_ME_BEFORE_ENCRYPTING" ]]; then
  echo "ERROR: secret.yaml is not filled in / not encrypted yet. Aborting." >&2
  exit 1
fi

echo "==> Writing ${DEPLOY_DIR}/.env (not committed to git)"
umask 077
cat > "${DEPLOY_DIR}/.env" <<EOF
OMNI_OIDC_CLIENT_SECRET=${OMNI_OIDC_CLIENT_SECRET}
EOF

echo "==> Syncing docker-compose.yml to ${DEPLOY_DIR}"
cp "$COMPOSE_FILE" "${DEPLOY_DIR}/docker-compose.yml"

echo "==> Pulling latest image and starting Omni"
cd "$DEPLOY_DIR"
docker compose pull
docker compose up -d

echo "==> Done."
echo "    Logs:   docker logs -f omni"
echo "    Verify: docker exec omni cat /etc/hosts | grep auth.lan"