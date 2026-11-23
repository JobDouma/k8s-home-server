variable "proxmox_api_token" {
  description = "Proxmox API token (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint. Transitional 192.168.x.x until mgmt is on VLAN 10; then https://10.10.10.21:8006/"
  type        = string
  default     = "https://10.10.10.22:8006/"
}

variable "proxmox_node" {
  type    = string
  default = "pve2"
}

variable "datastore" {
  type    = string
  default = "local-lvm"
}

variable "iso_datastore" {
  type    = string
  default = "local"
}

variable "talos_version" {
  description = "Talos version contract. Bumping this only affects NEW clusters; existing clusters keep their original secrets."
  type        = string
  default     = "v1.14.6"
}

variable "talos_schematic_id" {
  type    = string
  default = "46a5ffcc6627ec9bf37c6b2f13b290000d5ac2981e90b7160b5f2878f375ee8c"
}

# pve2/pve3 have a single NIC — the VM sits on the default vmbr0.
# If your switch port is an ACCESS port for VLAN 10, remove `vlan_id`
# from the module call below (double-tagging otherwise).
variable "bridge_name" {
  type    = string
  default = "vmbr0"
}

variable "vlan_id" {
  type    = number
  default = 10
}