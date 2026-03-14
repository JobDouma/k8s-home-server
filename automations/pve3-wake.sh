#!/bin/bash
set -euo pipefail

# ── Config ────────────────────────────────────────────────────
K8S_NODE="talos-cp-3"
PVE3_HOST="192.168.2.15"
LOG_TAG="pve3-wake"
NODE_READY_TIMEOUT=300
# Media deployments to nudge back to cp-3 after wake.
# These have a preferredDuringScheduling affinity for cp-3.
# Deleting the pod forces the scheduler to re-evaluate placement
# with cp-3 back in the pool — it will likely land on cp-3 again.
MEDIA_NAMESPACE="media"
MEDIA_DEPLOYMENTS=(
  "jellyfin"
)
# ─────────────────────────────────────────────────────────────

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*"; }

log "Starting wake sequence for pve3 / $K8S_NODE"

# ── Step 1: Wait for pve3 SSH ─────────────────────────────────
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

# ── Step 2: Wait for talos-cp-3 Ready ────────────────────────
log "Waiting for $K8S_NODE to become Ready..."
ELAPSED=0
until kubectl get node "$K8S_NODE" 2>/dev/null | grep -q " Ready"; do
  sleep 15
  ELAPSED=$((ELAPSED + 15))
  if [ $ELAPSED -ge $NODE_READY_TIMEOUT ]; then
    log "ERROR: $K8S_NODE did not become Ready after ${NODE_READY_TIMEOUT}s."
    exit 1
  fi
  log "Waiting for $K8S_NODE... (${ELAPSED}s)"
done
log "$K8S_NODE is Ready."

# ── Step 3: Uncordon ─────────────────────────────────────────
log "Uncordoning $K8S_NODE..."
kubectl uncordon "$K8S_NODE"

# ── Step 4: Give the scheduler a moment to settle ────────────
log "Waiting 30s for scheduler to settle after uncordon..."
sleep 30

# ── Step 5: Redeploy media apps back to cp-3 ─────────────────
# Rollout restart deletes pods one by one (respecting PDBs if present).
# The scheduler will place the new pod on cp-3 due to the preferred
# nodeAffinity already in the Jellyfin helmrelease.
log "Redeploying media apps to trigger scheduler re-evaluation..."
for DEPLOY in "${MEDIA_DEPLOYMENTS[@]}"; do
  if kubectl get deployment "$DEPLOY" -n "$MEDIA_NAMESPACE" &>/dev/null; then
    log "  Rolling restart: $MEDIA_NAMESPACE/$DEPLOY"
    kubectl rollout restart deployment/"$DEPLOY" -n "$MEDIA_NAMESPACE"
    kubectl rollout status deployment/"$DEPLOY" -n "$MEDIA_NAMESPACE" --timeout=120s \
      || log "  WARNING: rollout status timed out for $DEPLOY — check manually."
  else
    log "  Skipping $DEPLOY — not found in $MEDIA_NAMESPACE."
  fi
done

log "Wake sequence complete. talos-cp-3 is back in full rotation."
