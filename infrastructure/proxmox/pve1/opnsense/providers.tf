terraform {
  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.26"
    }
  }
}

# ─────────────────────────────────────────────────────────────────
# OPNsense provider
# ─────────────────────────────────────────────────────────────────
# TRANSITIONAL URI
# Today: 192.168.2.200 (WAN-side IP on the dev LAN) – use this until
# 10.10.10.1 is reachable from the switch (Phase 1 & 2 complete).
# Final: 10.10.10.1 (MGMT VLAN gateway).
#
# Flip this only after:
#   1. VLAN 10 interface is live in OPNsense and has 10.10.10.1/24.
#   2. Bootstrap NIC (vtnet2) has been removed from the VM.
#   3. You can reach https://10.10.10.1 from a VLAN-10 tagged port.
# ─────────────────────────────────────────────────────────────────
provider "opnsense" {
  uri            = "https://10.10.10.1"   # ← change to 192.168.2.200 if not yet reachable
  api_key        = var.opnsense_api_key
  api_secret     = var.opnsense_api_secret
  allow_insecure = true
}