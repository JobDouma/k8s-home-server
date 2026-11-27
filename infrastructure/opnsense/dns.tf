# ─────────────────────────────────────────────────────────────────
# DNS host overrides — authoritative records for MetalLB VIPs
# ─────────────────────────────────────────────────────────────────
# These are NOT DHCP clients (no MAC). They are VIPs owned by
# OPNsense / MetalLB. Without these records clients would need to
# hard-code 10.10.10.53 and 10.10.10.100, which defeats the whole
# point of the VIP.
#
# Unbound answers these queries directly before any upstream lookup,
# so every VLAN that uses OPNsense as its resolver gets the right
# answer regardless of which VLAN the client sits on.
# ─────────────────────────────────────────────────────────────────

resource "opnsense_unbound_host_override" "blocky_vip" {
  enabled     = true
  description = "Blocky DNS VIP (MetalLB) — referenced by home_to_blocky_vip"
  hostname    = "blocky"
  domain      = "lan"          # matches Kea domain_name in dhcp.tf
  type        = "A"
  server      = "10.10.10.53"  # Blocky VIP
}

resource "opnsense_unbound_host_override" "traefik_vip" {
  enabled     = true
  description = "Traefik ingress VIP (MetalLB)"
  hostname    = "traefik"
  domain      = "lan"
  type        = "A"
  server      = "10.10.10.100" # Traefik VIP
}