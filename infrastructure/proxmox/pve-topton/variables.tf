
# Proxmox connection

variable "proxmox_endpoint" {
  type    = string
  default = "https://10.10.10.20:8006/"
}

variable "proxmox_api_token" {
  description = "Proxmox API token (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  type    = string
  default = "pve1"
}

variable "vm_datastore_id" {
  description = "Proxmox storage for VM disks."
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore_id" {
  description = "Proxmox storage for ISOs."
  type        = string
  default     = "local"
}

# Talos

variable "cluster_name" {
  type    = string
  default = "home"
}

variable "talos_version" {
  description = "Talos OS version for Image Factory and machine configuration."
  type        = string
  default     = "v1.14.6"
}

variable "talos_extensions" {
  description = "Official Talos system extensions."
  type        = list(string)

  default = [
    "siderolabs/qemu-guest-agent"
  ]
}

# Network

variable "mgmt_vlan_id" {
  type    = number
  default = 10
}

variable "lan_nics" {
  type    = list(string)
  default = ["nic1", "nic2", "nic3", "nic4", "nic5"]
}

variable "vlan_ids" {
  description = "VLAN IDs carried on the LAN trunk."
  type        = list(number)
  default     = [10, 20, 30, 40, 50]
}
