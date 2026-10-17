terraform {
  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.26"
    }
  }
}

# URI is a variable so the transitional → final switch is a .env.local
# change, not a code change.
#
# Transitional: https://192.168.2.200   (WAN-side bootstrap IP)
# Final:        https://10.10.10.1      (MGMT VLAN gateway)
#
# Flip only after:
#   1. VLAN 10 interface is live in OPNsense with 10.10.10.1/24.
#   2. Bootstrap NIC (vtnet2) has been removed from the VM.
#   3. `curl -k https://10.10.10.1` succeeds from a VLAN-10 tagged port.
provider "opnsense" {
  uri            = var.opnsense_uri
  api_key        = var.opnsense_api_key
  api_secret     = var.opnsense_api_secret
  allow_insecure = true
}