# ── Proxmox connection ────────────────────────────────────────────
variable "proxmox_api_token" {
  description = "Proxmox API token for pve2"
  type        = string
  sensitive   = true
}

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint for pve2 (transitional until mgmt moves to VLAN 10)"
  type        = string
  default     = "https://192.168.2.12:8006/"   # ← verify pve2's current IP
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

# ── Talos ─────────────────────────────────────────────────────────
variable "talos_version" {
  type    = string
  default = "v1.14.2"
}

variable "talos_schematic_id" {
  type    = string
  default = "46a5ffcc6627ec9bf37c6b2f13b290000d5ac2981e90b7160b5f2878f375ee8c"
}

# ── Network ───────────────────────────────────────────────────────
variable "lan_bridge" {
  description = "Bridge the worker VM attaches to (must be VLAN-aware for VLAN 10)"
  type        = string
  default     = "vmbr1"
}

# ── Worker ────────────────────────────────────────────────────────
variable "worker" {
  description = "Talos worker definition for this host"
  type = object({
    name        = string
    vm_id       = number
    cores       = number
    memory      = number
    disk_size   = number
    vlan_id     = number
    mac_address = string
  })
  default = {
    name        = "talos-wk-1"
    vm_id       = 121
    cores       = 4
    memory      = 8192
    disk_size   = 100
    vlan_id     = 10
    mac_address = "BC:24:11:AA:BB:01"   # ← must match the DHCP reservation
  }
}