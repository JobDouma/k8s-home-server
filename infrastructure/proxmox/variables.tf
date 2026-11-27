variable "proxmox_endpoint" {
  type    = string
  default = "https://10.10.10.20:8006/"
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "vm_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "iso_datastore_id" {
  type    = string
  default = "local"
}

variable "cluster_name" {
  type    = string
  default = "home"
}

variable "talos_version" {
  type    = string
  default = "v1.14.6"
}

variable "talos_extensions" {
  type    = list(string)
  default = ["siderolabs/qemu-guest-agent"]
}

variable "cluster_vip" {
  type    = string
  default = null
}

variable "network_gateway" {
  description = "Default gateway for Talos control-plane nodes (OPNsense LAN interface)."
  type        = string
  default     = "10.10.10.1"
}

variable "vm_revision" {
  description = "Bump this to force full recreation of every Talos VM, machine and agent step."
  type        = number
  default     = 1
}