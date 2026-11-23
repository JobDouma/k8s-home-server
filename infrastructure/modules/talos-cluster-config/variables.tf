variable "cluster_name" {
  description = "Name of the Talos cluster."
  type        = string
}

variable "control_plane_nodes" {
  description = "Map of control-plane nodes (name => IP). The first node is used for bootstrap."
  type = map(object({
    ip  = string
    mac = string
  }))
}

variable "cluster_vip" {
  description = "Floating VIP for the Kubernetes API, e.g. 10.10.10.29. Must be outside the DHCP range."
  type        = string
  default     = null
}

variable "talos_version" {
  description = "Talos version contract passed from the root module."
  type        = string
}

variable "install_disk" {
  description = "Disk device path for Talos installation."
  type        = string
  default     = "/dev/sda"
}