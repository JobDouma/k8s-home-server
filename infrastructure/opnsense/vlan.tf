# ─────────────────────────────────────────────────────────────────
# VLANs on the LAN trunk (vtnet1)
# ─────────────────────────────────────────────────────────────────
# ⚠️  optN numbering in firewall.tf, dhcp.tf, nat.tf is derived from
#     the order these VLANs are assigned in OPNsense.
#
#   opt1 → MGMT   (tag 10)
#   opt2 → IOT    (tag 20)
#   opt3 → HOME   (tag 30)
#   opt4 → GUEST  (tag 40)
#   opt5 → CAMERA (tag 50)
#
# Every resource has `prevent_destroy = true` to keep the assignment
# order stable.  See the original comments for the full rationale.
# ─────────────────────────────────────────────────────────────────

resource "opnsense_interfaces_vlan" "mgmt" {
  description = "MGMT - Tag 10"
  tag         = var.vlans.mgmt.tag
  priority    = 0
  parent      = "vtnet1"
  lifecycle { prevent_destroy = true }
}

resource "opnsense_interfaces_vlan" "iot" {
  description = "IOT - Tag 20"
  tag         = var.vlans.iot.tag
  priority    = 0
  parent      = "vtnet1"
  lifecycle { prevent_destroy = true }
}

resource "opnsense_interfaces_vlan" "home" {
  description = "HOME - Tag 30"
  tag         = var.vlans.home.tag
  priority    = 0
  parent      = "vtnet1"
  lifecycle { prevent_destroy = true }
}

resource "opnsense_interfaces_vlan" "guest" {
  description = "GUEST - Tag 40"
  tag         = var.vlans.guest.tag
  priority    = 0
  parent      = "vtnet1"
  lifecycle { prevent_destroy = true }
}

resource "opnsense_interfaces_vlan" "camera" {
  description = "CAMERA - Tag 50"
  tag         = var.vlans.camera.tag
  priority    = 0
  parent      = "vtnet1"
  lifecycle { prevent_destroy = true }
}

# ─────────────────────────────────────────────────────────────────
# WAN / ISP VLAN — DISABLED until the old router is removed
# ─────────────────────────────────────────────────────────────────
# Uncomment and adjust only after the ONT is moved directly to the
# OPNsense WAN NIC (vtnet0) and the old router is out of the path.
#
# resource "opnsense_interfaces_vlan" "wan_odido" {
#   description = "Odido internet"
#   tag         = 300
#   priority    = 0
#   parent      = "vtnet0"
#   lifecycle { prevent_destroy = true }
# }