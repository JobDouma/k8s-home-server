variable "proxmox_api_token" {
  description = "Proxmox API token (user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  default = "pve1"
}

variable "datastore" {
  description = "Proxmox storage for VM disks"
  default     = "local-lvm"
}

# WAN — dedicated uplink to Fiber ONT
variable "wan_nic" {
  description = "Physical NIC carrying the WAN uplink (NIC0)"
  default     = "nic0"
}

# LAN — all house-facing NICs, bridged together into one VLAN-aware switch
variable "lan_nics" {
  description = "House-facing NICs (rooms + 10G uplink to Horaco)"
  type        = list(string)
  default     = ["nic1", "nic2", "nic3", "nic4", "nic5"]
}

variable "vlan_ids" {
  description = "VLAN IDs carried on the LAN trunk"
  default     = "10 20 30 40 50"
}