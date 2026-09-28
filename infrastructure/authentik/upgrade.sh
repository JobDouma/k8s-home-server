#!/usr/bin/env bash
set -euo pipefail

# Deploys/upgrades the Authentik docker-compose stack.
# Decrypts secret.yaml -> .env and blueprints.sops.yaml -> ./blueprints/,
# then runs docker compose. Idempotent, safe to re-run.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

SECRET_FILE="${REPO_DIR}/secret.yaml"
BLUEPRINTS_SOPS="${REPO_DIR}/blueprints.sops.yaml"
BLUEPRINTS_DIR="${REPO_DIR}/blueprints"
ENV_FILE="${REPO_DIR}/.env"

command -v sops   >/dev/null || { echo "ERROR: sops not found on PATH"   >&2; exit 1; }
command -v yq     >/dev/null || { echo "ERROR: yq not found on PATH"     >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: docker not found on PATH" >&2; exit 1; }

[[ -f "$SECRET_FILE"     ]] || { echo "ERROR: missing $SECRET_FILE"     >&2; exit 1; }
[[ -f "$BLUEPRINTS_SOPS" ]] || { echo "ERROR: missing $BLUEPRINTS_SOPS" >&2; exit 1; }

echo "==> Decrypting ${SECRET_FILE} -> ${ENV_FILE}"
TMP_ENV="$(mktemp)"
sops -d "$SECRET_FILE" \
  | yq -r '.stringData | to_entries | .[] | "\(.key)=\(.value)"' \
  > "$TMP_ENV"

# Sanity check: password must be present, otherwise postgres will be created
# with a blank password.
if ! grep -q '^AUTHENTIK_POSTGRESQL__PASSWORD=' "$TMP_ENV"; then
  echo "ERROR: AUTHENTIK_POSTGRESQL__PASSWORD missing from decrypted secret." >&2
  rm -f "$TMP_ENV"
  exit 1
fi

chmod 600 "$TMP_ENV"
mv "$TMP_ENV" "$ENV_FILE"

echo "==> Decrypting blueprints -> ${BLUEPRINTS_DIR}/"
mkdir -p "$BLUEPRINTS_DIR"
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  echo "    -> $f"
  sops -d "$BLUEPRINTS_SOPS" \
    | yq -r ".stringData[\"$f\"]" \
    > "${BLUEPRINTS_DIR}/$f"
  chmod 644 "${BLUEPRINTS_DIR}/$f"
done < <(sops -d "$BLUEPRINTS_SOPS" | yq -r '.stringData | keys | .[]')

echo "==> Bringing up data tier (postgres, redis)"
docker compose --env-file "$ENV_FILE" up -d postgres redis

echo "==> Waiting for postgres to accept connections..."
for i in $(seq 1 30); do
  if docker exec authentik-postgres pg_isready -U authentik -d authentik -q 2>/dev/null; then
    break
  fi
  sleep 2
  if [[ "$i" -eq 30 ]]; then
    echo "ERROR: postgres did not become ready in 60s" >&2
    exit 1
  fi
done

echo "==> Validating compose config"
docker compose --env-file "$ENV_FILE" config >/dev/null

echo "==> Bringing up app tier"
docker compose --env-file "$ENV_FILE" up -d --pull always --remove-orphans

echo "==> Status"
docker compose ps

echo "==> Done."
echo "    Server  logs: docker logs -f authentik-server"
echo "    Worker  logs: docker logs -f authentik-worker"
echo "    Health  check: curl -fsS http://127.0.0.1:9000/-/health/live/ -o /dev/null && echo ok"