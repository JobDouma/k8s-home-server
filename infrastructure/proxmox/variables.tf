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

# ── Flux bootstrap ──────────────────────────────────────────────

variable "github_token" {
  description = "GitHub PAT with repo:read+write scope for Flux bootstrap"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub user or organisation"
  type        = string
  default     = "JobDouma"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "k8s-home-server"
}

variable "github_branch" {
  description = "Branch Flux syncs from"
  type        = string
  default     = "main"
}

variable "flux_path" {
  description = "Path inside the git repo where Flux cluster config lives"
  type        = string
  default     = "clusters/talos-home"
}

variable "flux_version" {
  description = "Flux version to install"
  type        = string
  default     = "v2.4.0"
}