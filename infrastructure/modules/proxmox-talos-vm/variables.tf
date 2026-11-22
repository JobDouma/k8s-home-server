variable "node_name" { type = string }
variable "vm_id" { type = number }
variable "vm_name" { type = string }
variable "talos_version" { type = string }
variable "talos_schematic" { type = string }
variable "datastore" { type = string }
variable "iso_datastore" { type = string }
variable "bridge_name" { type = string }
variable "vlan_id" { type = number }
variable "mac_address" {
  description = "Static MAC for the VM NIC. Must match the OPNsense DHCP reservation."
  type        = string
  default     = null
}