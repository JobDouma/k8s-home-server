variable "opnsense_api_key" {
  description = "OPNsense API key"
  type        = string
  sensitive   = true
}

variable "opnsense_api_secret" {
  description = "OPNsense API secret"
  type        = string
  sensitive   = true
}

# ── MGMT VLAN host addresses referenced in firewall rules ────────
# These are the hosts that CAMERA and other VLANs are allowed to
# reach.  Set the real IPs here rather than hard-coding in
# firewall.tf so there is one place to look.
variable "nvr_ip" {
  description = "IP address of the NVR / camera recorder on the MGMT VLAN"
  type        = string
  default     = "10.10.10.200"
}

variable "home_assistant_ip" {
  description = "IP address of Home Assistant on the MGMT VLAN"
  type        = string
  default     = "10.10.10.201"
}

# ── VLAN definitions ──────────────────────────────────────────────
variable "vlans" {
  description = "VLAN definitions for the home network"
  type = map(object({
    tag         = number
    description = string
    subnet      = string
    gateway     = string
  }))
  default = {
    mgmt = {
      tag         = 10
      description = "Management / Infrastructure"
      subnet      = "10.10.10.0/24"
      gateway     = "10.10.10.1"
    }
    iot = {
      tag         = 20
      description = "IoT Devices"
      subnet      = "10.10.20.0/24"
      gateway     = "10.10.20.1"
    }
    home = {
      tag         = 30
      description = "Home / Clients"
      subnet      = "10.10.30.0/24"
      gateway     = "10.10.30.1"
    }
    guest = {
      tag         = 40
      description = "Guest Network"
      subnet      = "10.10.40.0/24"
      gateway     = "10.10.40.1"
    }
    camera = {
      tag         = 50
      description = "Camera / NVR"
      subnet      = "10.10.50.0/24"
      gateway     = "10.10.50.1"
    }
  }
}

# ── DHCP pool ranges per VLAN ──────────────────────────────────────
# NOTE: the MGMT pool starts at .101 on purpose to stay clear of
# the Traefik MetalLB VIP at 10.10.10.100.  Do not lower this
# without also moving the Traefik VIP off the pool.
variable "dhcp_pools" {
  description = "DHCP pool ranges (start-end) per VLAN"
  type = map(object({
    range_from = string
    range_to   = string
  }))
  default = {
    mgmt = {
      range_from = "10.10.10.101"
      range_to   = "10.10.10.199"
    }
    iot = {
      range_from = "10.10.20.100"
      range_to   = "10.10.20.199"
    }
    home = {
      range_from = "10.10.30.100"
      range_to   = "10.10.30.199"
    }
    guest = {
      range_from = "10.10.40.100"
      range_to   = "10.10.40.199"
    }
    camera = {
      range_from = "10.10.50.100"
      range_to   = "10.10.50.199"
    }
  }
}