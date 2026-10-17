output "vlan_ids" {
  description = "Created VLAN interface IDs"
  value = {
    mgmt   = opnsense_interfaces_vlan.mgmt.id
    iot    = opnsense_interfaces_vlan.iot.id
    home   = opnsense_interfaces_vlan.home.id
    guest  = opnsense_interfaces_vlan.guest.id
    camera = opnsense_interfaces_vlan.camera.id
  }
}

output "dhcp_subnet_ids" {
  description = "Created Kea DHCP subnet IDs"
  value = {
    mgmt   = opnsense_kea_dhcpv4_subnet.mgmt.id
    iot    = opnsense_kea_dhcpv4_subnet.iot.id
    home   = opnsense_kea_dhcpv4_subnet.home.id
    guest  = opnsense_kea_dhcpv4_subnet.guest.id
    camera = opnsense_kea_dhcpv4_subnet.camera.id
  }
}

output "firewall_rule_ids" {
  description = "Created firewall rule IDs"
  value = {
    # MGMT
    icmp_debug_mgmt     = opnsense_firewall_filter.icmp_debug_mgmt.id
    mgmt_allow_all      = opnsense_firewall_filter.mgmt_allow_all.id

    # IOT
    iot_dhcp            = opnsense_firewall_filter.iot_dhcp.id
    iot_dns             = opnsense_firewall_filter.iot_dns.id
    iot_ntp             = opnsense_firewall_filter.iot_ntp.id
    iot_ha              = opnsense_firewall_filter.iot_ha.id
    iot_mdns            = opnsense_firewall_filter.iot_mdns.id
    iot_block_internal  = opnsense_firewall_filter.iot_block_internal.id
    iot_block_192       = opnsense_firewall_filter.iot_block_rfc1918_192.id
    iot_block_172       = opnsense_firewall_filter.iot_block_rfc1918_172.id
    iot_internet        = opnsense_firewall_filter.iot_internet.id

    # HOME
    home_dhcp           = opnsense_firewall_filter.home_dhcp.id
    home_dns            = opnsense_firewall_filter.home_dns.id
    home_ntp            = opnsense_firewall_filter.home_ntp.id
    home_ha             = opnsense_firewall_filter.home_ha.id
    home_jellyfin       = opnsense_firewall_filter.home_jellyfin.id
    home_truenas_smb    = opnsense_firewall_filter.home_truenas_smb.id
    home_truenas_nfs    = opnsense_firewall_filter.home_truenas_nfs.id
    home_to_mgmt_https  = opnsense_firewall_filter.home_to_mgmt_https.id
    home_to_mgmt_8006   = opnsense_firewall_filter.home_to_mgmt_proxmox.id
    home_to_mgmt_ssh    = opnsense_firewall_filter.home_to_mgmt_ssh.id
    home_block_internal = opnsense_firewall_filter.home_block_internal.id
    home_block_192      = opnsense_firewall_filter.home_block_rfc1918_192.id
    home_block_172      = opnsense_firewall_filter.home_block_rfc1918_172.id
    home_internet       = opnsense_firewall_filter.home_internet.id

    # GUEST
    guest_dhcp           = opnsense_firewall_filter.guest_dhcp.id
    guest_dns            = opnsense_firewall_filter.guest_dns.id
    guest_ntp            = opnsense_firewall_filter.guest_ntp.id
    guest_block_internal = opnsense_firewall_filter.guest_block_internal.id
    guest_block_192      = opnsense_firewall_filter.guest_block_rfc1918_192.id
    guest_block_172      = opnsense_firewall_filter.guest_block_rfc1918_172.id
    guest_internet       = opnsense_firewall_filter.guest_internet.id

    # CAMERA
    camera_dhcp          = opnsense_firewall_filter.camera_dhcp.id
    camera_dns           = opnsense_firewall_filter.camera_dns.id
    camera_ntp           = opnsense_firewall_filter.camera_ntp.id
    camera_nvr_rtsp      = opnsense_firewall_filter.camera_nvr_rtsp.id
    camera_ha            = opnsense_firewall_filter.camera_ha.id
    camera_default_deny  = opnsense_firewall_filter.camera_default_deny.id
  }
}