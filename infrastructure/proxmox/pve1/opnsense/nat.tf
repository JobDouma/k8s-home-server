# ─────────────────────────────────────────────────────────────────
# Outbound NAT — one rule per VLAN (hybrid mode)
# Each VLAN's traffic is NAT'd to the WAN IP before leaving the router.
# ─────────────────────────────────────────────────────────────────

resource "opnsense_firewall_nat" "mgmt_outbound" {
  interface   = "wan"
  protocol    = "any"
  source      = { net = var.vlans.mgmt.subnet }
  target      = { ip = "wanip" }
  description = "NAT MGMT VLAN to WAN"
  sequence    = 10
}

resource "opnsense_firewall_nat" "iot_outbound" {
  interface   = "wan"
  protocol    = "any"
  source      = { net = var.vlans.iot.subnet }
  target      = { ip = "wanip" }
  description = "NAT IOT VLAN to WAN"
  sequence    = 20
}

resource "opnsense_firewall_nat" "home_outbound" {
  interface   = "wan"
  protocol    = "any"
  source      = { net = var.vlans.home.subnet }
  target      = { ip = "wanip" }
  description = "NAT HOME VLAN to WAN"
  sequence    = 30
}

resource "opnsense_firewall_nat" "guest_outbound" {
  interface   = "wan"
  protocol    = "any"
  source      = { net = var.vlans.guest.subnet }
  target      = { ip = "wanip" }
  description = "NAT GUEST VLAN to WAN"
  sequence    = 40
}

resource "opnsense_firewall_nat" "camera_outbound" {
  interface   = "wan"
  protocol    = "any"
  source      = { net = var.vlans.camera.subnet }
  target      = { ip = "wanip" }
  description = "NAT CAMERA VLAN to WAN"
  sequence    = 50
}