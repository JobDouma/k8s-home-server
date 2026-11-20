variable "switch_host" {
  description = "Post-bootstrap management IP. Will be the ONLY IP on the mgmt VLAN after migration."
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
  description = "Factory IP used only as a diagnostic hint when switch_host is unreachable."
  type        = string
  default     = "192.168.2.1"
}

variable "uplink_port" {
  description = "SFP+ port to Proxmox/OPNsense (trunk). Horaco naming: te1..te6."
  type        = string
  default     = "te6"

  validation {
    condition     = can(regex("^te[1-6]$", var.uplink_port))
    error_message = "uplink_port must be te1..te6 (SFP+ ports)."
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
  description = "VLAN ID -> list of copper ports that become TRUE untagged hybrid members. mgi1-mgi8 are all MGMT per user request."
  type        = map(list(string))
  default = {
    "10" = ["mgi1", "mgi2", "mgi3", "mgi4", "mgi5", "mgi6", "mgi7", "mgi8"]  # all 8 ports MGMT
    "20" = []                                                                 # no IOT ports (all reassigned to MGMT)
    "30" = ["mgi9", "mgi10", "mgi11"]
    "40" = ["mgi13"]
    "50" = ["mgi14", "mgi15"]
  }
}

variable "lag_port_map" {
  description = "LAG definition: lag id -> { members = [...], vlan = untagged VLAN ID }. Empty to disable (default — MGI2/MGI3 are standalone MGMT). Set to { \"1\" = { members = [\"mgi2\",\"mgi3\"], vlan = 10 } } to restore TrueNAS LAG, and remove mgi2/mgi3 from vlan_port_map[\"10\"]."
  type = map(object({
    members = list(string)
    vlan    = number
  }))
  default = {}
}

variable "mgmt_vlan" {
  description = "VLAN ID that will host the switch management SVI."
  type        = number
  default     = 10
}

variable "mgmt_ip" {
  description = "IP address to assign to the management SVI (mgmt_vlan)."
  type        = string
  default     = "10.10.10.3"
}

variable "mgmt_subnet_mask" {
  description = "Subnet mask for the management SVI. KT-NOS wants space-separated mask, not CIDR."
  type        = string
  default     = "255.255.255.0"
}

variable "bootstrap_ip" {
  description = "Temporary secondary IP assigned to the mgmt VLAN SVI so the SVI comes up before the primary IP is moved from VLAN 1. Removed after migration. Must be in the mgmt subnet and not collide with any other device."
  type        = string
  default     = "10.10.10.5"
}

variable "host_vlan_ip" {
  description = "IP assigned to the Terraform host's temporary VLAN sub-interface. Must be in the mgmt subnet, not collide with switch or OPNsense."
  type        = string
  default     = "10.10.10.250"
}

variable "host_vlan_prefix" {
  description = "Prefix length for host_vlan_ip."
  type        = number
  default     = 24
}

variable "terraform_host_port" {
  description = "Switch port where the Terraform host is cabled. Made hybrid (VLAN 1 untagged + mgmt VLAN tagged) so the host can reach the switch before and after migration."
  type        = string
  default     = "mgi12"

  validation {
    condition     = can(regex("^mgi([1-9]|1[0-9]|2[0-4])$", var.terraform_host_port))
    error_message = "terraform_host_port must be mgi1..mgi24."
  }
}

variable "migrate_mgmt_to_vlan10" {
  description = "If true, remove the IP from VLAN 1 after bringing up the mgmt VLAN SVI. Default true."
  type        = bool
  default     = true
}

variable "dry_run" {
  description = "If true, only read state (show vlan / running-config). Change nothing."
  type        = bool
  default     = true
}

variable "no_save_first" {
  description = "If true, apply to running-config but DO NOT save to flash. Re-apply with false to persist."
  type        = bool
  default     = true
}