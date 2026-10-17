# ─────────────────────────────────────────────────────────────────
# Interface name assumption
# ─────────────────────────────────────────────────────────────────
# This file assumes OPNsense assigned VLANs to interfaces in this
# order after manual assignment:
#
#   opt1 → VLAN 10 (MGMT)
#   opt2 → VLAN 20 (IOT)
#   opt3 → VLAN 30 (HOME)
#   opt4 → VLAN 40 (GUEST)
#   opt5 → VLAN 50 (CAMERA)
#
# If you re-order them in Interfaces → Assignments you MUST update
# every rule below. There is no way around this until the provider
# supports interface assignment as a resource.
#
# See ./vlan.tf for the prevent_destroy rationale that keeps this
# ordering stable across applies.
# ─────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────
# mDNS NOTE
# ─────────────────────────────────────────────────────────────────
# OPNsense does NOT forward multicast between interfaces by default.
# The `iot_mdns` rule below will match but the traffic still will
# not be relayed. To make Chromecast / AirPlay / HomeKit discovery
# work across VLANs you MUST install the `os-mdns-repeater` plugin
# (System → Firmware → Plugins) and enable it on the MGMT, IOT, and
# HOME interfaces.
#
# The firewall rule is still required to permit the UDP/5353 flow
# once the repeater is active — it just isn't sufficient on its own.
# ─────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────
# Firewall rules — deny by default, explicit allow per VLAN
# OPNsense evaluates rules top-down; place more specific rules first.
#
# Each non-MGMT VLAN has the following structure:
#   * DHCP / DNS / NTP to the local gateway (bootstrap)
#   * Specific service allowances to MGMT
#   * A block rule for 10.10.0.0/16, 192.168.0.0/16, 172.16.0.0/12
#   * A final allow for everything else (i.e. Internet)
#
# RFC1918 blocks prevent VLANs from leaking sideways into the
# 192.168.2.0/24 WAN-side dev LAN, the old-router subnet, or any
# 172.16.x.x gear you haven't migrated yet.
# ─────────────────────────────────────────────────────────────────

# ── MGMT VLAN (opt1) ──────────────────────────────────────────────
# Mgmt is the trusted network: allow all outbound, allow all internal.

resource "opnsense_firewall_filter" "icmp_debug_mgmt" {
  description = "MGMT: allow ICMP for debugging"
  interface   = { interface = ["opt1"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "ICMP"
    source      = { net = "10.10.10.0/24" }
    destination = { net = "10.10.10.0/24" }
  }
  sequence = 5
}

resource "opnsense_firewall_filter" "mgmt_allow_all" {
  description = "MGMT: allow all traffic"
  interface   = { interface = ["opt1"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.10.0/24" }
    destination = { net = "any" }
  }
  sequence = 10
}

# ── IOT VLAN (opt2) ───────────────────────────────────────────────
# IoT: DHCP, DNS, NTP, HA, mDNS; block RFC1918 sideways;
# Internet is allowed after the internal blocks.

resource "opnsense_firewall_filter" "iot_dhcp" {
  description = "IOT: allow DHCP to OPNsense"
  interface   = { interface = ["opt2"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "UDP"
    source      = { net = "any", port = "68" }
    destination = { net = "10.10.20.1", port = "67" }
  }
  sequence = 19
}

resource "opnsense_firewall_filter" "iot_dns" {
  description = "IOT: allow DNS to OPNsense"
  interface   = { interface = ["opt2"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "TCP/UDP"
    source      = { net = "10.10.20.0/24" }
    destination = { net = "10.10.20.1", port = "53" }
  }
  sequence = 20
}

resource "opnsense_firewall_filter" "iot_ntp" {
  description = "IOT: allow NTP to OPNsense"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"
    source    = { net = "10.10.20.0/24" }
    destination = { net = "10.10.20.1", port = "123" }
  }
  sequence = 21
}

resource "opnsense_firewall_filter" "iot_ha" {
  description = "IOT: allow access to Home Assistant"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"
    source    = { net = "10.10.20.0/24" }
    destination = { net = "10.10.10.0/24", port = "8123" }
  }
  sequence = 22
}

# mDNS for device discovery (Chromecast, AirPlay, HomeKit, etc.)
# Requires the os-mdns-repeater plugin — see header note.
resource "opnsense_firewall_filter" "iot_mdns" {
  description = "IOT: allow mDNS discovery (requires os-mdns-repeater)"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"
    source    = { net = "10.10.20.0/24" }
    destination = { net = "224.0.0.251", port = "5353" }
  }
  sequence = 23
}

resource "opnsense_firewall_filter" "iot_block_internal" {
  description = "IOT: block all other 10.10.0.0/16 traffic"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.20.0/24" }
    destination = { net = "10.10.0.0/16" }
  }
  sequence = 29
}

resource "opnsense_firewall_filter" "iot_block_rfc1918_192" {
  description = "IOT: block RFC1918 192.168.0.0/16"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.20.0/24" }
    destination = { net = "192.168.0.0/16" }
  }
  sequence = 30
}

resource "opnsense_firewall_filter" "iot_block_rfc1918_172" {
  description = "IOT: block RFC1918 172.16.0.0/12"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.20.0/24" }
    destination = { net = "172.16.0.0/12" }
  }
  sequence = 31
}

resource "opnsense_firewall_filter" "iot_internet" {
  description = "IOT: allow Internet access"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.20.0/24" }
    destination = { net = "any" }
  }
  sequence = 32
}

# ── HOME VLAN (opt3) ──────────────────────────────────────────────
# Home: DHCP, DNS, NTP, HA UI, Jellyfin, TrueNAS SMB/NFS, mgmt UIs.
# Block RFC1918 sideways, then allow Internet.

resource "opnsense_firewall_filter" "home_dhcp" {
  description = "HOME: allow DHCP to OPNsense"
  interface   = { interface = ["opt3"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "UDP"
    source      = { net = "any", port = "68" }
    destination = { net = "10.10.30.1", port = "67" }
  }
  sequence = 39
}

resource "opnsense_firewall_filter" "home_dns" {
  description = "HOME: allow DNS to OPNsense"
  interface   = { interface = ["opt3"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "TCP/UDP"
    source      = { net = "10.10.30.0/24" }
    destination = { net = "10.10.30.1", port = "53" }
  }
  sequence = 40
}

resource "opnsense_firewall_filter" "home_ntp" {
  description = "HOME: allow NTP to OPNsense"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "10.10.30.1", port = "123" }
  }
  sequence = 41
}

resource "opnsense_firewall_filter" "home_ha" {
  description = "HOME: allow Home Assistant UI"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "10.10.10.0/24", port = "8123" }
  }
  sequence = 42
}

resource "opnsense_firewall_filter" "home_jellyfin" {
  description = "HOME: allow Jellyfin"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "10.10.10.0/24", port = "8096" }
  }
  sequence = 43
}

resource "opnsense_firewall_filter" "home_truenas_smb" {
  description = "HOME: allow TrueNAS SMB"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "10.10.10.10", port = "445" }
  }
  sequence = 44
}

resource "opnsense_firewall_filter" "home_truenas_nfs" {
  description = "HOME: allow TrueNAS NFS"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "10.10.10.10", port = "2049" }
  }
  sequence = 45
}

# Allow Home VLAN to manage infrastructure on Mgmt VLAN
resource "opnsense_firewall_filter" "home_to_mgmt_https" {
  description = "HOME: allow HTTPS to Mgmt (Proxmox, OPNsense, TrueNAS, switches)"
  interface   = { interface = ["opt3"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "TCP"
    source      = { net = "10.10.30.0/24" }
    destination = { net = "10.10.10.0/24", port = "443" }
  }
  sequence = 46   # before home_block_internal at 49
}

resource "opnsense_firewall_filter" "home_to_mgmt_proxmox" {
  description = "HOME: allow Proxmox UI/API (8006)"
  interface   = { interface = ["opt3"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "TCP"
    source      = { net = "10.10.30.0/24" }
    destination = { net = "10.10.10.0/24", port = "8006" }
  }
  sequence = 47
}

resource "opnsense_firewall_filter" "home_to_mgmt_ssh" {
  description = "HOME: allow SSH to Mgmt devices"
  interface   = { interface = ["opt3"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "TCP"
    source      = { net = "10.10.30.0/24" }
    destination = { net = "10.10.10.0/24", port = "22" }
  }
  sequence = 48
}

resource "opnsense_firewall_filter" "home_block_internal" {
  description = "HOME: block all other 10.10.0.0/16 traffic"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "10.10.0.0/16" }
  }
  sequence = 49
}

resource "opnsense_firewall_filter" "home_block_rfc1918_192" {
  description = "HOME: block RFC1918 192.168.0.0/16"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "192.168.0.0/16" }
  }
  sequence = 50
}

resource "opnsense_firewall_filter" "home_block_rfc1918_172" {
  description = "HOME: block RFC1918 172.16.0.0/12"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "172.16.0.0/12" }
  }
  sequence = 51
}

resource "opnsense_firewall_filter" "home_internet" {
  description = "HOME: allow Internet access"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.30.0/24" }
    destination = { net = "any" }
  }
  sequence = 52
}

# ── GUEST VLAN (opt4) ─────────────────────────────────────────────
# Guest: DHCP, DNS, NTP, block RFC1918, then Internet only.

resource "opnsense_firewall_filter" "guest_dhcp" {
  description = "GUEST: allow DHCP to OPNsense"
  interface   = { interface = ["opt4"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "UDP"
    source      = { net = "any", port = "68" }
    destination = { net = "10.10.40.1", port = "67" }
  }
  sequence = 59
}

resource "opnsense_firewall_filter" "guest_dns" {
  description = "GUEST: allow DNS to OPNsense"
  interface   = { interface = ["opt4"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "TCP/UDP"
    source      = { net = "10.10.40.0/24" }
    destination = { net = "10.10.40.1", port = "53" }
  }
  sequence = 60
}

resource "opnsense_firewall_filter" "guest_ntp" {
  description = "GUEST: allow NTP to OPNsense"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"
    source    = { net = "10.10.40.0/24" }
    destination = { net = "10.10.40.1", port = "123" }
  }
  sequence = 61
}

resource "opnsense_firewall_filter" "guest_block_internal" {
  description = "GUEST: block all 10.10.0.0/16 traffic"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.40.0/24" }
    destination = { net = "10.10.0.0/16" }
  }
  sequence = 69
}

resource "opnsense_firewall_filter" "guest_block_rfc1918_192" {
  description = "GUEST: block RFC1918 192.168.0.0/16"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.40.0/24" }
    destination = { net = "192.168.0.0/16" }
  }
  sequence = 70
}

resource "opnsense_firewall_filter" "guest_block_rfc1918_172" {
  description = "GUEST: block RFC1918 172.16.0.0/12"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.40.0/24" }
    destination = { net = "172.16.0.0/12" }
  }
  sequence = 71
}

resource "opnsense_firewall_filter" "guest_internet" {
  description = "GUEST: allow Internet only"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.40.0/24" }
    destination = { net = "any" }
  }
  sequence = 72
}

# ── CAMERA VLAN (opt5) ────────────────────────────────────────────
# Camera: DHCP, DNS, NTP, RTSP to NVR, HA UI, then default deny.
# The default-deny below blocks CAMERA → internal AND CAMERA → WAN.
# If your cameras need cloud connectivity, add a specific allow rule
# above sequence 89 — do NOT remove the default deny.

resource "opnsense_firewall_filter" "camera_dhcp" {
  description = "CAMERA: allow DHCP to OPNsense"
  interface   = { interface = ["opt5"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "UDP"
    source      = { net = "any", port = "68" }
    destination = { net = "10.10.50.1", port = "67" }
  }
  sequence = 79
}

resource "opnsense_firewall_filter" "camera_dns" {
  description = "CAMERA: allow DNS to OPNsense"
  interface   = { interface = ["opt5"] }
  filter = {
    action      = "pass"
    direction   = "in"
    protocol    = "TCP/UDP"
    source      = { net = "10.10.50.0/24" }
    destination = { net = "10.10.50.1", port = "53" }
  }
  sequence = 80
}

resource "opnsense_firewall_filter" "camera_ntp" {
  description = "CAMERA: allow NTP to OPNsense"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "UDP"
    source    = { net = "10.10.50.0/24" }
    destination = { net = "10.10.50.1", port = "123" }
  }
  sequence = 81
}

# Destination = NVR — see variables.tf → var.nvr_ip
resource "opnsense_firewall_filter" "camera_nvr_rtsp" {
  description = "CAMERA: allow RTSP to NVR"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"
    source    = { net = "10.10.50.0/24" }
    destination = { net = var.nvr_ip, port = "554" }
  }
  sequence = 82
}

# Destination = Home Assistant — see variables.tf → var.home_assistant_ip
resource "opnsense_firewall_filter" "camera_ha" {
  description = "CAMERA: allow Home Assistant UI"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "pass"
    direction = "in"
    protocol  = "TCP"
    source    = { net = "10.10.50.0/24" }
    destination = { net = var.home_assistant_ip, port = "8123" }
  }
  sequence = 83
}

# Default deny — blocks everything not matched above, including WAN.
resource "opnsense_firewall_filter" "camera_default_deny" {
  description = "CAMERA: default deny (internal + WAN)"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "block"
    direction = "in"
    protocol  = "any"
    source    = { net = "10.10.50.0/24" }
    destination = { net = "any" }
  }
  sequence = 89
}