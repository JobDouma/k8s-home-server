# ─────────────────────────────────────────────────────────────────
# Kea DHCPv4 — one subnet per VLAN
# ─────────────────────────────────────────────────────────────────
# GitOps-first: every addressable device gets a DHCP reservation here
# so there is one place to look for "what is at 10.10.10.x".
#
# Exceptions (static configured on the device itself):
#   - OPNsense (is the DHCP server)
#   - pve-topton (runs OPNsense as a VM — cannot depend on it)
#   - MetalLB / Traefik / Blocky VIPs (no MAC, not DHCP clients)
#
# IMPORTANT: the MGMT DHCP pool starts at 10.10.10.101, not .100,
# because the Traefik MetalLB VIP lives at 10.10.10.100.  See
# variables.tf → dhcp_pools.mgmt.
# ─────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────
# Subnets (unchanged)
# ─────────────────────────────────────────────────────────────────

resource "opnsense_kea_dhcpv4_subnet" "mgmt" {
  subnet          = var.vlans.mgmt.subnet
  description     = "MGMT - Management / Infrastructure"
  pools           = ["${var.dhcp_pools.mgmt.range_from} - ${var.dhcp_pools.mgmt.range_to}"]
  routers         = [var.vlans.mgmt.gateway]
  dns_servers     = [var.vlans.mgmt.gateway]
  domain_name     = "lan"
  auto_collect    = false
  match_client_id = false
}

resource "opnsense_kea_dhcpv4_subnet" "iot" {
  subnet          = var.vlans.iot.subnet
  description     = "IOT - IoT Devices"
  pools           = ["${var.dhcp_pools.iot.range_from} - ${var.dhcp_pools.iot.range_to}"]
  routers         = [var.vlans.iot.gateway]
  dns_servers     = [var.vlans.iot.gateway]
  domain_name     = "lan"
  auto_collect    = false
  match_client_id = false
}

resource "opnsense_kea_dhcpv4_subnet" "home" {
  subnet          = var.vlans.home.subnet
  description     = "HOME - Home / Clients"
  pools           = ["${var.dhcp_pools.home.range_from} - ${var.dhcp_pools.home.range_to}"]
  routers         = [var.vlans.home.gateway]
  dns_servers     = [var.vlans.home.gateway]
  domain_name     = "lan"
  auto_collect    = false
  match_client_id = false
}

resource "opnsense_kea_dhcpv4_subnet" "guest" {
  subnet          = var.vlans.guest.subnet
  description     = "GUEST - Guest Network"
  pools           = ["${var.dhcp_pools.guest.range_from} - ${var.dhcp_pools.guest.range_to}"]
  routers         = [var.vlans.guest.gateway]
  dns_servers     = [var.vlans.guest.gateway]
  domain_name     = "lan"
  auto_collect    = false
  match_client_id = false
}

resource "opnsense_kea_dhcpv4_subnet" "camera" {
  subnet          = var.vlans.camera.subnet
  description     = "CAMERA - Camera / NVR"
  pools           = ["${var.dhcp_pools.camera.range_from} - ${var.dhcp_pools.camera.range_to}"]
  routers         = [var.vlans.camera.gateway]
  dns_servers     = [var.vlans.camera.gateway]
  domain_name     = "lan"
  auto_collect    = false
  match_client_id = false
}

# ─────────────────────────────────────────────────────────────────
# Static DHCP reservations — MGMT VLAN (10)
# ─────────────────────────────────────────────────────────────────
# Excluded on purpose (static, not DHCP clients):
#   pve-topton (10.10.10.20)   — static in /etc/network/interfaces
#   blocky-vip (10.10.10.53)   — MetalLB VIP, no MAC
#   traefik-vip (10.10.10.100) — MetalLB VIP, no MAC
#
# ⚠️  Reservations with TODO MACs are commented out until the real
#     MAC addresses are known.  Uncomment and fill in the MAC when ready.
# ─────────────────────────────────────────────────────────────────

# resource "opnsense_kea_dhcpv4_reservation" "truenas" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = "10.10.10.10"
#   mac_address  = "TODO:TN:MGMT:MAC:00"
#   hostname     = "truenas"
#   description  = "TrueNAS Scale storage"
# }

# resource "opnsense_kea_dhcpv4_reservation" "omni" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = "10.10.10.11"
#   mac_address  = "TODO:OMNI:MGMT:MAC:00"
#   hostname     = "omni"
#   description  = "Ubuntu / Omni VM"
# }

# resource "opnsense_kea_dhcpv4_reservation" "rpi" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = "10.10.10.12"
#   mac_address  = "TODO:PI:MGMT:MAC:00"
#   hostname     = "rpi"
#   description  = "Raspberry Pi 4B"
# }

# resource "opnsense_kea_dhcpv4_reservation" "pve_hp1" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = "10.10.10.21"
#   mac_address  = "TODO:HP1:MGMT:MAC:00"
#   hostname     = "pve-hp1"
#   description  = "HP ProDesk 1 (worker .31)"
# }

# resource "opnsense_kea_dhcpv4_reservation" "pve_hp2" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = "10.10.10.22"
#   mac_address  = "TODO:HP2:MGMT:MAC:00"
#   hostname     = "pve-hp2"
#   description  = "HP ProDesk 2 (worker .32)"
# }

# resource "opnsense_kea_dhcpv4_reservation" "pve_lenovo" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = "10.10.10.23"
#   mac_address  = "TODO:LEN:MGMT:MAC:00"
#   hostname     = "pve-lenovo"
#   description  = "Lenovo M75q (worker .33)"
# }

# Talos control plane — keep. This is the reservation you already
# proved works end-to-end.
resource "opnsense_kea_dhcpv4_reservation" "talos_cp" {
  subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
  ip_address   = "10.10.10.30"
  mac_address  = "BC:24:11:C5:51:77"
  hostname     = "talos-cp-1"
  description  = "Talos control-plane"
}

# Talos workers — add once the VMs exist. Same pattern as the CP.
# resource "opnsense_kea_dhcpv4_reservation" "talos_worker_hp1" {
#   subnet_id   = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address  = "10.10.10.31"
#   mac_address = "TODO"
#   hostname    = "talos-worker-1"
#   description = "Talos worker on HP ProDesk 1"
# }
#
# resource "opnsense_kea_dhcpv4_reservation" "talos_worker_hp2" {
#   subnet_id   = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address  = "10.10.10.32"
#   mac_address = "TODO"
#   hostname    = "talos-worker-2"
#   description = "Talos worker on HP ProDesk 2"
# }
#
# resource "opnsense_kea_dhcpv4_reservation" "talos_worker_lenovo" {
#   subnet_id   = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address  = "10.10.10.33"
#   mac_address = "TODO"
#   hostname    = "talos-worker-3"
#   description = "Talos worker on Lenovo"
# }

# ─────────────────────────────────────────────────────────────────
# Hosts referenced by firewall rules in firewall.tf
# Fill the MAC in and uncomment to make the IP stable.
# ─────────────────────────────────────────────────────────────────

# NVR / camera recorder — referenced by camera_nvr_rtsp
# resource "opnsense_kea_dhcpv4_reservation" "nvr" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = var.nvr_ip
#   mac_address  = "TODO:NVR:MGMT:MAC:00"
#   hostname     = "nvr"
#   description  = "NVR / camera recorder (referenced by camera_nvr_rtsp)"
# }

# Home Assistant — referenced by iot_ha, home_ha, camera_ha
# resource "opnsense_kea_dhcpv4_reservation" "home_assistant" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = var.home_assistant_ip
#   mac_address  = "TODO:HA:MGMT:MAC:00"
#   hostname     = "home-assistant"
#   description  = "Home Assistant (referenced by iot_ha, home_ha, camera_ha)"
# }

# Network gear — DHCP reservations on MGMT VLAN

# resource "opnsense_kea_dhcpv4_reservation" "horaco_switch" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = "10.10.10.3"
#   mac_address  = "TODO:SW:MGMT:MAC:00"
#   hostname     = "horaco-core"
#   description  = "Horaco ZX-SWTG3624AS core switch"
# }

# resource "opnsense_kea_dhcpv4_reservation" "omada_eap770" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
#   ip_address   = "10.10.10.4"
#   mac_address  = "TODO:AP:MGMT:MAC:00"
#   hostname     = "eap770"
#   description  = "Omada EAP770 (mgmt)"
# }

resource "opnsense_kea_dhcpv4_reservation" "TL-SG108PE" {
  subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
  ip_address   = "10.10.10.5"
  mac_address  = "60:15:6F:87:84:9F"
  hostname     = "TL-SG108PE"
  description  = "TP-Link TL-SG108PE switch"
}

# ─────────────────────────────────────────────────────────────────
# Static DHCP reservations — IOT VLAN (20)
# ─────────────────────────────────────────────────────────────────

# resource "opnsense_kea_dhcpv4_reservation" "shelly_sleeping_room" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.iot.id
#   ip_address   = "10.10.20.20"
#   mac_address  = "TODO:SH:20:20:20:00"
#   hostname     = "shelly-sleeping"
#   description  = "Shelly Plus 2PM Gen4 — Sleeping Room 1"
# }

# resource "opnsense_kea_dhcpv4_reservation" "shelly_office" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.iot.id
#   ip_address   = "10.10.20.21"
#   mac_address  = "TODO:SH:20:20:21:00"
#   hostname     = "shelly-office"
#   description  = "Shelly Plus 2PM Gen4 — Office"
# }

# resource "opnsense_kea_dhcpv4_reservation" "sensy_sleeping_room" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.iot.id
#   ip_address   = "10.10.20.30"
#   mac_address  = "TODO:SE:20:20:30:00"
#   hostname     = "sensy-sleeping"
#   description  = "Sensy One E1 Pro — Sleeping Room 1"
# }

# resource "opnsense_kea_dhcpv4_reservation" "sensy_office" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.iot.id
#   ip_address   = "10.10.20.31"
#   mac_address  = "TODO:SE:20:20:31:00"
#   hostname     = "sensy-office"
#   description  = "Sensy One E1 Pro — Office"
# }

# ─────────────────────────────────────────────────────────────────
# Static DHCP reservations — HOME VLAN (30)
# ─────────────────────────────────────────────────────────────────

# resource "opnsense_kea_dhcpv4_reservation" "desktop" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.home.id
#   ip_address   = "10.10.30.50"
#   mac_address  = "TODO:DESK:30:50:00:00"
#   hostname     = "desktop"
#   description  = "Desktop i5-8600K (AI inference)"
# }

resource "opnsense_kea_dhcpv4_reservation" "dell_g5" {
  subnet_id    = opnsense_kea_dhcpv4_subnet.mgmt.id
  ip_address   = "10.10.10.51"        # outside the .101–.199 pool, no VIP
  mac_address  = "00:4E:01:99:3C:B8"
  hostname     = "dell-g5"
  description  = "Dell G5 5590 (light inference)"
}

# resource "opnsense_kea_dhcpv4_reservation" "sonos_arc" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.home.id
#   ip_address   = "10.10.30.60"
#   mac_address  = "TODO:SO:30:60:00:00"
#   hostname     = "sonos-arc"
#   description  = "Sonos Arc Ultra"
# }

# ─────────────────────────────────────────────────────────────────
# Static DHCP reservations — CAMERA VLAN (50)
# ─────────────────────────────────────────────────────────────────

# resource "opnsense_kea_dhcpv4_reservation" "reolink_facade" {
#   subnet_id    = opnsense_kea_dhcpv4_subnet.camera.id
#   ip_address   = "10.10.50.20"
#   mac_address  = "TODO:RE:50:20:00:00"
#   hostname     = "reolink-facade"
#   description  = "Reolink camera — facade"
# }