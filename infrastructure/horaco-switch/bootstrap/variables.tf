variable "switch_host" {
  description = "Management IP of the switch. Use the factory default right after a reset."
  type        = string
  default     = "192.168.2.1"

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.switch_host))
    error_message = "switch_host must be a dotted-quad IPv4 address."
  }
}

variable "switch_user" {
  description = "SSH username for the switch."
  type        = string
  default     = "admin"
}

variable "switch_password" {
  description = "SSH password for the switch. Supply via TF_VAR_switch_password env var (never commit)."
  type        = string
  sensitive   = true
}

variable "switch_new_ip" {
  description = "Target management IP address (host part, no mask)."
  type        = string
  default     = "10.10.10.3"

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.switch_new_ip))
    error_message = "switch_new_ip must be a dotted-quad IPv4 address."
  }
}

variable "switch_subnet_bits" {
  description = "Prefix length for the new IP (e.g. 24 for /24)."
  type        = number
  default     = 24

  validation {
    condition     = var.switch_subnet_bits >= 8 && var.switch_subnet_bits <= 30
    error_message = "switch_subnet_bits must be between 8 and 30."
  }
}

variable "vlan_interface" {
  description = "Name of the management VLAN interface as reported by `show running-config`."
  type        = string
  default     = "vlan1"
}

variable "force_reconfigure" {
  description = "If true, run the configuration even when the switch already answers at the new IP."
  type        = bool
  default     = false
}