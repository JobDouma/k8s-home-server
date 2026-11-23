variable "node_name" {
  description = "Proxmox node that hosts the VM."
  type        = string
}

variable "vm_id" {
  type = number
}

variable "vm_name" {
  type = string
}

variable "talos_version" {
  description = "Talos OS version of the ISO (e.g. v1.14.6). Used only to trigger VM replacement."
  type        = string
}

variable "iso_file_id" {
  description = "Proxmox file ID of the Talos ISO (e.g. local:iso/talos-v1.14.6-....iso)."
  type        = string
}

variable "vm_datastore_id" {
  type = string
}

variable "bridge_name" {
  description = "Bridge name as a plain string (e.g. vmbr1)."
  type        = string
}

variable "vlan_id" {
  type = number
}

variable "mac_address" {
  description = "Static MAC. Must match the OPNsense DHCP reservation."
  type        = string
}

variable "cpu_cores" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk_size_gb" {
  type    = number
  default = 100
}