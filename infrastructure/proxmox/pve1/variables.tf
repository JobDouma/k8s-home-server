variable "proxmox_api_token" {
  description = "Proxmox API token (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint. Transitional 192.168.2.11 until mgmt is on VLAN 10; then https://10.10.10.20:8006/"
  type        = string
  default     = "https://192.168.2.11:8006/"
}

variable "proxmox_node" {
  type    = string
  default = "pve1"
}

variable "datastore" {
  description = "Proxmox storage for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore" {
  description = "Proxmox storage for ISOs (must have 'iso' content enabled)"
  type        = string
  default     = "local"
}

# ── Talos ─────────────────────────────────────────────────────────
variable "talos_version" {
  description = "Talos Linux version"
  type        = string
  default     = "v1.14.2"
}

variable "talos_schematic_id" {
  description = "Talos Image Factory schematic ID"
  type        = string
  default     = "46a5ffcc6627ec9bf37c6b2f13b290000d5ac2981e90b7160b5f2878f375ee8c"
}

# ── WAN ───────────────────────────────────────────────────────────
variable "wan_nic" {
  description = "Physical NIC carrying the WAN uplink (NIC0)"
  type        = string
  default     = "nic0"
}

# ── LAN ───────────────────────────────────────────────────────────
variable "lan_nics" {
  description = "House-facing NICs (rooms + 10G uplink to Horaco)"
  type        = list(string)
  default     = ["nic1", "nic2", "nic3", "nic4", "nic5"]
}

variable "vlan_ids" {
  description = "VLAN IDs carried on the LAN trunk (space-separated)"
  type        = string
  default     = "10 20 30 40 50"
}