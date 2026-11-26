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
  description = "Talos OS version used for ISO download and as the config-generation contract."
  type        = string
  default     = "v1.14.6"
}

variable "talos_extensions" {
  type    = list(string)
  default = ["siderolabs/qemu-guest-agent"]
}

variable "cluster_vip" {
  description = "Optional floating VIP for the Kubernetes API. Null = use bootstrap node IP."
  type        = string
  default     = null
}