variable "switch_host" {
  description = "IP used to reach the switch when the run starts (current management IP)."
  type        = string
  default     = "10.10.10.3"

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.switch_host))
    error_message = "switch_host must be a dotted-quad IPv4 address."
  }
}

variable "switch_user" {
  type    = string
  default = "admin"
}

variable "switch_password" {
  description = "Supply via TF_VAR_switch_password env var (never commit)."
  type        = string
  sensitive   = true
}

variable "factory_ip" {
  description = "Factory IP - only used in diagnostic messages."
  type        = string
  default     = "192.168.2.1"
}

variable "uplink_port" {
  description = "SFP+ trunk port to OPNsense/router (VLANs 10-50 tagged)."
  type        = string
  default     = "te1"

  validation {
    condition     = can(regex("^te[1-6]$", var.uplink_port))
    error_message = "uplink_port must be te1..te6."
  }
}

variable "vlan_names" {
  description = "VLAN ID -> name (for readability in running-config)."
  type        = map(string)
  default = {
    "10" = "MGMT"
    "20" = "IOT"
    "30" = "HOME"
    "40" = "GUEST"
    "50" = "CAMERA"
  }
}

variable "vlan_port_map" {
  description = "VLAN ID -> list of copper ports that become untagged hybrid members (with PVID). LAG members must NOT be listed here."
  type        = map(list(string))
  default = {
    # MGMT access ports (mgi2 + mgi3 are in lag 1 for TrueNAS)
    "10" = ["mgi1", "mgi4", "mgi5", "mgi6", "mgi7", "mgi8"]
    # no IOT ports
    "20" = []
    # all remaining copper ports are HOME
    "30" = ["mgi9", "mgi10", "mgi11", "mgi12",
      "mgi13", "mgi14", "mgi15", "mgi16",
      "mgi17", "mgi18", "mgi19", "mgi20",
    "mgi21", "mgi22", "mgi23", "mgi24"]
    # no dedicated GUEST / CAMERA ports
    "40" = []
    "50" = []
  }
}

variable "lag_port_map" {
  description = "LAG: lag id -> { members = [...], vlan = number }. Empty = disabled."
  type = map(object({
    members = list(string)
    vlan    = number
  }))
  default = {
    # TrueNAS 2.5GbE NICs
    "1" = {
      members = ["mgi2", "mgi3"]
      vlan    = 10
    }
  }
}

variable "lag_mode" {
  description = "Extra arguments for the per-member 'lag <id>' command, e.g. 'mode active' for LACP. Empty = bare 'lag <id>' (rejected by this switch)."
  type        = string
  default     = "mode active"
}

variable "mgmt_vlan" {
  description = "VLAN ID hosting the switch management SVI."
  type        = number
  default     = 10
}

variable "mgmt_ip" {
  description = "IP on the management SVI (final management IP)."
  type        = string
  default     = "10.10.10.3"
}

variable "mgmt_subnet_mask" {
  description = "Subnet mask for the SVI (dotted, not CIDR - KT-NOS wants this form)."
  type        = string
  default     = "255.255.255.0"
}

variable "host_vlan_ip" {
  description = "Fallback IP for the Terraform host's VLAN sub-interface (only used if switch is unreachable via default route - likely won't work in WSL)."
  type        = string
  default     = "10.10.10.250"
}

variable "host_vlan_prefix" {
  type    = number
  default = 24
}

variable "migrate_mgmt_to_vlan10" {
  description = "Move the mgmt IP from vlan1 to the mgmt VLAN SVI (removes it from vlan1 first)."
  type        = bool
  default     = true
}

variable "dry_run" {
  description = "If true, only reads state (show vlan / running-config). Changes nothing."
  type        = bool
  default     = true
}

variable "save_after_verify" {
  description = "If true, save to flash only AFTER the switch is confirmed reachable on mgmt_ip. If false, changes stay in running-config and a power cycle rolls them back."
  type        = bool
  default     = false
}