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
#   3. Downloads the .deb package from GitHub releases
#   4. Verifies the download using GitHub's official SHA256 checksum
#   5. Stops the service, installs, reloads systemd, restarts
#   6. Confirms the new version is running correctly
#   7. Cleans up downloaded files
#
# WHEN TO RUN:
#   After merging a Renovate PR that bumps version.yaml.
#   Renovate handles detection — this script handles the actual install.
#
# REQUIREMENTS:
#   - curl, sha256sum, dpkg, systemctl
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
# Step 3: Download .deb and checksum file from GitHub
# -------------------------------------------------------
BASE_URL="https://github.com/coder/code-server/releases/download/v${TARGET_VERSION}"
DEB_FILE="code-server_${TARGET_VERSION}_amd64.deb"
CHECKSUM_FILE="code-server_${TARGET_VERSION}_amd64.deb.sha256"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT  # always clean up temp dir on exit

info "Downloading ${DEB_FILE}..."
curl -fL --progress-bar -o "${TMPDIR}/${DEB_FILE}" "${BASE_URL}/${DEB_FILE}" \
  || error "Download failed. Check your internet connection or that v${TARGET_VERSION} exists on GitHub."

info "Downloading checksum file..."
curl -fsSL -o "${TMPDIR}/${CHECKSUM_FILE}" "${BASE_URL}/${CHECKSUM_FILE}" \
  || error "Checksum file not found for v${TARGET_VERSION}. The release may be incomplete."

# -------------------------------------------------------
# Step 4: Verify SHA256 checksum — abort if mismatch
# -------------------------------------------------------
info "Verifying SHA256 checksum..."
EXPECTED_HASH=$(awk '{print $1}' "${TMPDIR}/${CHECKSUM_FILE}")
ACTUAL_HASH=$(sha256sum "${TMPDIR}/${DEB_FILE}" | awk '{print $1}')

if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
  error "Checksum mismatch! The downloaded file may be corrupted or tampered with.
  Expected: ${EXPECTED_HASH}
  Actual:   ${ACTUAL_HASH}"
fi

success "Checksum verified."

# -------------------------------------------------------
# Step 5: Verify the .deb package is valid before installing
# -------------------------------------------------------
info "Validating .deb package integrity..."
dpkg-deb --info "${TMPDIR}/${DEB_FILE}" > /dev/null 2>&1 \
  || error "The .deb file is invalid or corrupt. Aborting before any changes are made."

success "Package structure looks valid."

# -------------------------------------------------------
# Step 6: Stop service, install, reload systemd, restart
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
# Step 7: Confirm the new version is actually running
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