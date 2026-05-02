#!/bin/bash
# =============================================================================
# code-server upgrade script
# =============================================================================
# USAGE:
#   bash infrastructure/vs-code/upgrade.sh
#
# HOW IT WORKS:
#   1. Reads the target version from version.yaml (managed by Renovate)
#   2. Compares it to the currently installed version — skips if already up to date
#   3. Fetches the SHA256 checksum from the GitHub Releases API
#   4. Downloads the .deb package from GitHub releases
#   5. Verifies the download against the API-sourced checksum
#   6. Stops the service, installs, reloads systemd, restarts
#   7. Confirms the new version is running correctly
#   8. Cleans up downloaded files
#
# NOTE ON CHECKSUMS:
#   As of v4.117.0, code-server no longer ships a separate .sha256 sidecar
#   file alongside the .deb. This script fetches checksums from the GitHub
#   Releases API instead (the 'digest' field on each release asset), which
#   is the authoritative source going forward.
#
# WHEN TO RUN:
#   After merging a Renovate PR that bumps version.yaml.
#   Renovate handles detection — this script handles the actual install.
#
# REQUIREMENTS:
#   - curl, sha256sum, dpkg, systemctl
#   - python3 or jq (for JSON parsing — python3 is the fallback if jq is absent)
#   - sudo access
# =============================================================================

set -euo pipefail

# -------------------------------------------------------
# Helpers
# -------------------------------------------------------
info()    { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
warn()    { echo "⚠️  $*"; }
error()   { echo "❌ $*" >&2; exit 1; }

# -------------------------------------------------------
# Dependency check
# -------------------------------------------------------
for cmd in curl sha256sum dpkg; do
  command -v "$cmd" &>/dev/null || error "Required command not found: ${cmd}. Install it and retry."
done

# jq is preferred but not required — pure bash fallback is used if absent
if command -v jq &>/dev/null; then
  USE_JQ=true
else
  warn "jq not found — using bash fallback for JSON parsing (consider: sudo apt-get install jq)"
  USE_JQ=false
fi

# Extract sha256 hash for a named asset from GitHub releases API JSON.
# Handles both jq and a grep/sed fallback for systems without jq.
extract_digest() {
  local json="$1"
  local filename="$2"
  if [[ "$USE_JQ" == true ]]; then
    echo "$json" \
      | jq -r --arg name "$filename" \
        '.assets[] | select(.name == $name) | .digest // empty' \
      | grep -oP '(?<=sha256:)[a-f0-9]+'
  else
    # python3 is available on all supported Ubuntu versions and handles both
    # compact and pretty-printed JSON correctly.
    echo "$json" | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
for a in data.get('assets', []):
    if a['name'] == '${filename}':
        d = a.get('digest') or ''
        m = re.search(r'sha256:([a-f0-9]+)', d)
        if m: print(m.group(1))
        break
"
  fi
}

# -------------------------------------------------------
# Step 1: Read target version from version.yaml
# -------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/version.yaml"

if [[ ! -f "$VERSION_FILE" ]]; then
  error "version.yaml not found at ${VERSION_FILE}. Are you running from the right directory?"
fi

TARGET_VERSION=$(grep 'code_server_version' "$VERSION_FILE" | grep -oP '[\d.]+')

if [[ -z "$TARGET_VERSION" ]]; then
  error "Could not parse code_server_version from ${VERSION_FILE}. Check the file format."
fi

info "Target version from version.yaml: v${TARGET_VERSION}"

# -------------------------------------------------------
# Step 2: Check currently installed version — skip if same
# -------------------------------------------------------
if command -v code-server &>/dev/null; then
  INSTALLED_VERSION=$(code-server --version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)
  info "Currently installed: v${INSTALLED_VERSION}"

  if [[ "$INSTALLED_VERSION" == "$TARGET_VERSION" ]]; then
    success "code-server v${TARGET_VERSION} is already installed. Nothing to do."
    exit 0
  fi

  info "Upgrading v${INSTALLED_VERSION} → v${TARGET_VERSION}"
else
  info "code-server not currently installed — performing fresh install of v${TARGET_VERSION}"
fi

# -------------------------------------------------------
# Step 3: Fetch SHA256 checksum from the GitHub Releases API
#
# The separate .sha256 sidecar file was dropped as of v4.117.0.
# The GitHub Releases API returns a 'digest' field (e.g. "sha256:abc123...")
# for each asset, which is the authoritative checksum source.
# -------------------------------------------------------
DEB_FILE="code-server_${TARGET_VERSION}_amd64.deb"
API_URL="https://api.github.com/repos/coder/code-server/releases/tags/v${TARGET_VERSION}"

info "Fetching release metadata from GitHub API..."
RELEASE_JSON=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API_URL") \
  || error "Failed to reach GitHub API. Check your internet connection or that v${TARGET_VERSION} exists."

EXPECTED_HASH=$(extract_digest "$RELEASE_JSON" "$DEB_FILE")

if [[ -z "$EXPECTED_HASH" ]]; then
  error "Could not find a SHA256 digest for ${DEB_FILE} in the GitHub API response.
  The release may not exist, the asset name may have changed, or the API returned unexpected data.
  Check: ${API_URL}"
fi

info "Expected SHA256 from GitHub API: ${EXPECTED_HASH}"

# -------------------------------------------------------
# Step 4: Download the .deb package
# -------------------------------------------------------
BASE_URL="https://github.com/coder/code-server/releases/download/v${TARGET_VERSION}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT  # always clean up temp dir on exit

info "Downloading ${DEB_FILE}..."
curl -fL --progress-bar -o "${TMPDIR}/${DEB_FILE}" "${BASE_URL}/${DEB_FILE}" \
  || error "Download failed. Check your internet connection or that v${TARGET_VERSION} exists on GitHub."

# -------------------------------------------------------
# Step 5: Verify SHA256 checksum — abort if mismatch
# -------------------------------------------------------
info "Verifying SHA256 checksum..."
ACTUAL_HASH=$(sha256sum "${TMPDIR}/${DEB_FILE}" | awk '{print $1}')

if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
  error "Checksum mismatch! The downloaded file may be corrupted or tampered with.
  Expected: ${EXPECTED_HASH}
  Actual:   ${ACTUAL_HASH}"
fi

success "Checksum verified."

# -------------------------------------------------------
# Step 6: Verify the .deb package is valid before installing
# -------------------------------------------------------
info "Validating .deb package integrity..."
dpkg-deb --info "${TMPDIR}/${DEB_FILE}" > /dev/null 2>&1 \
  || error "The .deb file is invalid or corrupt. Aborting before any changes are made."

success "Package structure looks valid."

# -------------------------------------------------------
# Step 7: Stop service, install, reload systemd, restart
# -------------------------------------------------------
info "Stopping code-server service..."
sudo systemctl stop code-server@job

info "Installing code-server v${TARGET_VERSION}..."
sudo dpkg -i "${TMPDIR}/${DEB_FILE}"

info "Reloading systemd (picks up any service file changes)..."
sudo systemctl daemon-reload

info "Starting code-server service..."
sudo systemctl start code-server@job

# -------------------------------------------------------
# Step 8: Confirm the new version is actually running
# -------------------------------------------------------
sleep 2  # give the process a moment to start

if ! systemctl is-active --quiet code-server@job; then
  error "code-server service failed to start after upgrade! Check: journalctl -u code-server@job -n 50"
fi

RUNNING_VERSION=$(code-server --version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)

if [[ "$RUNNING_VERSION" != "$TARGET_VERSION" ]]; then
  warn "Service is running but reports version v${RUNNING_VERSION}, expected v${TARGET_VERSION}."
  warn "Try: sudo systemctl restart code-server@job"
else
  success "code-server v${RUNNING_VERSION} is running successfully."
fi

# Temp dir is cleaned up automatically by the trap above
success "Upgrade complete! Access your editor at http://192.168.2.12:8080"