#!/bin/bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────
K8S_NODE="talos-cp-3"
TALOS_NODE_IP="192.168.2.16"         # e.g. 192.168.1.x
TALOS_CONFIG="$HOME/.talos/config"
PVE3_HOST="192.168.2.15"                   # e.g. 192.168.1.y
LOG_TAG="pve3-sleep"
# ─────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*"; }

log "Starting sleep sequence for $K8S_NODE / pve3"

# Step 1: Cordon the node
log "Cordoning $K8S_NODE..."
kubectl cordon "$K8S_NODE"

# Step 2: Drain the node
log "Draining $K8S_NODE (this may take a minute)..."
kubectl drain "$K8S_NODE" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=5m \
  --skip-wait-for-delete-timeout=30

log "Drain complete."

# Step 3: Shut down Talos VM gracefully
log "Sending shutdown to Talos node $TALOS_NODE_IP..."
talosctl shutdown \
  --nodes "$TALOS_NODE_IP" \
  --talosconfig "$TALOS_CONFIG"

# Step 4: Wait for VM to fully power off before killing the host
log "Waiting 45s for VM to power off..."
sleep 45

# Step 5: Power off pve3
log "Powering off pve3 ($PVE3_HOST)..."
ssh -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    root@"$PVE3_HOST" "poweroff" || true

log "Sleep sequence complete. pve3 is shutting down."
