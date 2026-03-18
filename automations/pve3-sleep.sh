#!/bin/bash
set -uo pipefail
# ── Config ────────────────────────────────────────────────────
K8S_NODE="talos-cp-3"
TALOS_NODE_IP="192.168.2.16"
TALOS_CONFIG="$HOME/.talos/config"
PVE3_HOST="192.168.2.15"
LOG_TAG="pve3-sleep"
VM_POWEROFF_TIMEOUT=120   # seconds to wait for VM to power off
VM_PING_INTERVAL=5        # seconds between power-off checks
# ─────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*"; }
die()  { log "FATAL: $*"; exit 1; }
# ── Preflight checks ─────────────────────────────────────────
log "Starting sleep sequence for $K8S_NODE / pve3"
kubectl cluster-info --request-timeout=10s > /dev/null 2>&1 \
  || die "kubectl cannot reach the API server — aborting."
kubectl get node "$K8S_NODE" > /dev/null 2>&1 \
  || die "Node $K8S_NODE not found in cluster — aborting."
# ── Step 1: Cordon ───────────────────────────────────────────
log "Cordoning $K8S_NODE..."
kubectl cordon "$K8S_NODE" || log "Already cordoned, continuing."
# ── Step 2: Drain ────────────────────────────────────────────
log "Draining $K8S_NODE (timeout 5m)..."
kubectl drain "$K8S_NODE" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=5m \
  --skip-wait-for-delete-timeout=30 \

  || log "Drain exited non-zero (may be fine — checking stuck pods next)."
log "Drain complete."
# ── Step 3a: Force-delete stuck non-daemonset pods on this node ─
# DaemonSet pods are intentionally left by --ignore-daemonsets above.
# Force-deleting them causes ContainerStatusUnknown: the daemonset controller
# immediately recreates them into a node that is mid-shutdown.
# Only force-delete pods that are NOT owned by a DaemonSet.
log "Force-deleting any stuck non-daemonset pods on $K8S_NODE..."
STUCK_PODS=$(kubectl get pods -A \
  --field-selector="spec.nodeName=${K8S_NODE}" \
  -o json 2>/dev/null | \
  jq -r '
    .items[] |
    select(
      (.metadata.ownerReferences // []) |
      map(.kind) |
      contains(["DaemonSet"]) | not
    ) |
    .metadata.namespace + " " + .metadata.name
  ')
if [[ -z "$STUCK_PODS" ]]; then
  log "No stuck non-daemonset pods found."
else
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    NS=$(echo "$line" | awk '{print $1}')
    POD=$(echo "$line" | awk '{print $2}')
    log "  Force-deleting pod $NS/$POD"
    kubectl delete pod -n "$NS" "$POD" --force --grace-period=0 2>/dev/null || true
  done <<< "$STUCK_PODS"
fi
log "Cleanup complete."

# ── Step 3b: Clean ContainerStatusUnknown pods cluster-wide ──
log "Cleaning any pre-existing ContainerStatusUnknown pods cluster-wide..."
kubectl get pods -A -o json | \
  jq -r '
    .items[] |
    select(
      (.status.containerStatuses // [] + (.status.initContainerStatuses // [])) |
      any(.state.terminated.reason? == "ContainerStatusUnknown")
    ) |
    .metadata.namespace + " " + .metadata.name
  ' | while read -r NS POD; do
    [[ -z "$NS" ]] && continue
    log "  Deleting ContainerStatusUnknown pod: $NS/$POD"
    kubectl delete pod -n "$NS" "$POD" --force --grace-period=0 2>/dev/null || true
  done
  
# ── Step 4: Talos graceful shutdown ──────────────────────────
log "Sending graceful shutdown to Talos node $TALOS_NODE_IP..."
talosctl shutdown \
  --nodes "$TALOS_NODE_IP" \
  --talosconfig "$TALOS_CONFIG" \
  || die "talosctl shutdown failed — not powering off pve3."
# ── Step 5: Wait for VM to actually go dark ──────────────────
log "Waiting for $TALOS_NODE_IP to stop responding to ping (timeout ${VM_POWEROFF_TIMEOUT}s)..."
ELAPSED=0
while ping -c1 -W2 "$TALOS_NODE_IP" > /dev/null 2>&1; do
  if (( ELAPSED >= VM_POWEROFF_TIMEOUT )); then
    die "VM $TALOS_NODE_IP still pingable after ${VM_POWEROFF_TIMEOUT}s — not powering off pve3."
  fi
  log "  Still up... (${ELAPSED}s elapsed)"
  sleep "$VM_PING_INTERVAL"
  (( ELAPSED += VM_PING_INTERVAL ))
done
log "VM is down after ${ELAPSED}s."
# ── Step 6: Power off pve3 ───────────────────────────────────
log "Powering off pve3 ($PVE3_HOST)..."
ssh -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    root@"$PVE3_HOST" "poweroff" \
  || log "SSH poweroff returned non-zero (pve3 may already be shutting down)."
log "Sleep sequence complete. pve3 is shutting down."
