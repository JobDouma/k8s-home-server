#!/bin/bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────
K8S_NODE="talos-cp-3"
PVE3_HOST="192.168.2.15"
LOG_TAG="pve3-wake"
NODE_READY_TIMEOUT=300   # max seconds to wait for k8s node Ready
# ─────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*"; }

log "Starting wake sequence for pve3 / $K8S_NODE"
log "pve3 wakes via BIOS Auto On Time at 08:30 — waiting for SSH..."

# Step 1: Poll SSH until pve3 is reachable
ELAPSED=0
until ssh -o ConnectTimeout=5 \
          -o StrictHostKeyChecking=no \
          -o BatchMode=yes \
          root@"$PVE3_HOST" "echo up" &>/dev/null; do
  sleep 10
  ELAPSED=$((ELAPSED + 10))
  if [ $ELAPSED -ge 600 ]; then
    log "ERROR: pve3 did not respond to SSH after 600s. Aborting."
    exit 1
  fi
  log "Waiting for pve3... (${ELAPSED}s)"
done
log "pve3 is up."

# Step 2: VM 103 auto-starts via --onboot 1
# Wait for talos-cp-3 to boot and rejoin the cluster
log "Waiting for $K8S_NODE to become Ready in Kubernetes..."
ELAPSED=0
until kubectl get node "$K8S_NODE" 2>/dev/null | grep -q " Ready"; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  if [ $ELAPSED -ge $NODE_READY_TIMEOUT ]; then
    log "ERROR: $K8S_NODE did not become Ready after ${NODE_READY_TIMEOUT}s."
    exit 1
  fi
  log "Waiting for $K8S_NODE to be Ready... (${ELAPSED}s)"
done
log "$K8S_NODE is Ready."

# Step 3: Uncordon the node
log "Uncordoning $K8S_NODE..."
kubectl uncordon "$K8S_NODE"

log "Wake sequence complete. talos-cp-3 is back in full rotation."
