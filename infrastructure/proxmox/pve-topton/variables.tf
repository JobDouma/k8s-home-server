# ── Proxmox Connection ────────────────────────────────────────────
variable "proxmox_endpoint" {
  description = "Proxmox API endpoint for the topton node."
  type        = string
  default     = "https://10.10.10.20:8006/" # Mgmt VLAN 10 IP
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

variable "datastore" {
  description = "Proxmox storage for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore" {
  description = "Proxmox storage for ISOs"
  type        = string
  default     = "local"
}

# ── Talos ─────────────────────────────────────────────────────────
variable "talos_version" {
  description = "Talos version contract. Bumping this only affects NEW clusters; existing clusters keep their original secrets."
  type        = string
  default     = "v1.14.6"
}

variable "talos_schematic_id" {
  type    = string
  default = "46a5ffcc6627ec9bf37c6b2f13b290000d5ac2981e90b7160b5f2878f375ee8c"
  # This schematic ID is content-addressed on the extension list.
  # It remains stable across Talos version bumps. Validate extension
  # compatibility before changing talos_version.
}

# ── Network ───────────────────────────────────────────────────────
variable "lan_nics" {
  description = "House-facing NICs for the VLAN-aware bridge"
  type        = list(string)
  default     = ["nic1", "nic2", "nic3", "nic4", "nic5"]
}

variable "vlan_ids" {
  description = "VLAN IDs carried on the LAN trunk"
  type        = string
  default     = "10 20 30 40 50"
}