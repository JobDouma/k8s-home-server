resource "null_resource" "switch_vlan_config" {
  triggers = {
    switch_host          = var.switch_host
    uplink_port          = var.uplink_port
    vlan_names           = jsonencode(var.vlan_names)
    vlan_port_map        = jsonencode(var.vlan_port_map)
    lag_port_map         = jsonencode(var.lag_port_map)
    mgmt_vlan            = var.mgmt_vlan
    mgmt_ip              = var.mgmt_ip
    mgmt_subnet_mask     = var.mgmt_subnet_mask
    bootstrap_ip         = var.bootstrap_ip
    host_vlan_ip         = var.host_vlan_ip
    host_vlan_prefix     = var.host_vlan_prefix
    terraform_host_port  = var.terraform_host_port
    migrate_mgmt_to_vlan = var.migrate_mgmt_to_vlan10
    dry_run              = var.dry_run
    no_save_first        = var.no_save_first
    always_run           = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]

    command = <<-EOT
      set -e

      # Password comes from the Terraform variable now — no env var needed.
      SWITCH_PASS='${nonsensitive(var.switch_password)}'
      if [ -z "$SWITCH_PASS" ]; then
        echo "ERROR: switch_password is empty. Provide -var switch_password=... or TF_VAR_switch_password env var." >&2
        exit 1
      fi

      if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: must run as root (needs 'ip link'/'ip route'). Use: sudo tofu apply ..." >&2
        exit 1
      fi

      for c in ping ssh expect jq ip; do
        command -v "$c" >/dev/null 2>&1 || {
          echo "ERROR: '$c' not installed." >&2; exit 1; }
      done

      # ---------- detect host interface ----------
      HOST_IFACE=$(ip route get "${var.switch_host}" 2>/dev/null | awk '/dev/ {print $5; exit}')
      if [ -z "$HOST_IFACE" ]; then
        HOST_IFACE=$(ip route | awk '/default/ {print $5; exit}')
      fi
      if [ -z "$HOST_IFACE" ]; then
        echo "ERROR: could not detect host network interface." >&2
        exit 1
      fi
      echo "Detected host interface: $HOST_IFACE"

      HOST_VLAN_IFACE="$HOST_IFACE.${var.mgmt_vlan}"

      create_host_vlan() {
        if ip link show "$HOST_VLAN_IFACE" >/dev/null 2>&1; then
          echo "Host VLAN interface $HOST_VLAN_IFACE exists; reusing."
        else
          echo "Creating host VLAN interface $HOST_VLAN_IFACE (VLAN ${var.mgmt_vlan}) ..."
          ip link add link "$HOST_IFACE" name "$HOST_VLAN_IFACE" type vlan id "${var.mgmt_vlan}"
        fi
        ip addr add "${var.host_vlan_ip}/${var.host_vlan_prefix}" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        ip link set dev "$HOST_VLAN_IFACE" up
      }

      destroy_host_vlan() {
        ip route del "${var.switch_host}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        ip route del "${var.bootstrap_ip}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        if ip link show "$HOST_VLAN_IFACE" >/dev/null 2>&1; then
          ip link del "$HOST_VLAN_IFACE" 2>/dev/null || true
        fi
      }
      trap destroy_host_vlan EXIT

      # ---------- build payloads ----------
      VN_STR=$(echo '${jsonencode(var.vlan_names)}' | jq -r 'to_entries | map("\(.key):\(.value)") | join(",")')
      VP_STR=$(echo '${jsonencode(var.vlan_port_map)}' | jq -r 'to_entries | map(select(.value | length > 0)) | map("\(.key):\(.value | join("+"))") | join(",")')
      LAG_STR=$(echo '${jsonencode(var.lag_port_map)}' | jq -r 'to_entries | map("\(.key):\(.value.vlan):\(.value.members | join("+"))") | join(",")')

      EXPECT_SCRIPT=$(mktemp)
      trap 'rm -f "$EXPECT_SCRIPT"; destroy_host_vlan' EXIT

      cat > "$EXPECT_SCRIPT" <<'INNER_EOF'
set timeout 30
log_user 1

set mode            [lindex $argv 0]
set host            [lindex $argv 1]
set user            [lindex $argv 2]
set pass            [lindex $argv 3]
set uplink          [lindex $argv 4]
set vlan_names_str  [lindex $argv 5]
set vlan_ports_str  [lindex $argv 6]
set lag_str         [lindex $argv 7]
set mgmt_vlan       [lindex $argv 8]
set mgmt_ip         [lindex $argv 9]
set mgmt_mask       [lindex $argv 10]
set migrate_mgmt    [lindex $argv 11]
set host_port       [lindex $argv 12]
set bootstrap_ip    [lindex $argv 13]

array set vlan_names {}
foreach pair [split $vlan_names_str ","] {
    if {$pair eq ""} { continue }
    set kv [split $pair ":"]
    set vlan_names([lindex $kv 0]) [lindex $kv 1]
}

array set vlan_ports {}
foreach pair [split $vlan_ports_str ","] {
    if {$pair eq ""} { continue }
    set kv [split $pair ":"]
    set cleaned {}
    foreach p [split [lindex $kv 1] "+"] {
        if {$p ne ""} { lappend cleaned $p }
    }
    if {[llength $cleaned] > 0} { set vlan_ports([lindex $kv 0]) $cleaned }
}

array set lag_vlan {}
array set lag_members {}
foreach pair [split $lag_str ","] {
    if {$pair eq ""} { continue }
    set parts [split $pair ":"]
    set lagid [lindex $parts 0]
    set lag_vlan($lagid) [lindex $parts 1]
    set lag_members($lagid) [split [lindex $parts 2] "+"]
}

proc cmd {text prompt} {
    send "$text\r"
    expect {
        -re $prompt {
            if {[regexp {Invalid|Unknown|syntax error|% *[Ee]rror|command not found} $expect_out(buffer)]} {
                puts stderr "ERROR from switch after '$text': $expect_out(buffer)"
                exit 1
            }
        }
        -re "--More--" { send " "; exp_continue }
        timeout {
            puts stderr "TIMEOUT waiting for /$prompt/ after: $text"
            exit 1
        }
    }
}

proc soft_cmd {text prompt err_re} {
    send "$text\r"
    expect {
        -re $prompt { }
        -re $err_re { expect -re $prompt }
        -re "--More--" { send " "; exp_continue }
        timeout {
            puts stderr "TIMEOUT waiting for /$prompt/ after: $text"
            exit 1
        }
    }
}

proc login {host user pass} {
    global spawn_id
    spawn ssh -tt \
        -oHostKeyAlgorithms=+ssh-rsa \
        -oStrictHostKeyChecking=no \
        -oUserKnownHostsFile=/dev/null \
        -oPubkeyAuthentication=no \
        $user@$host

    expect {
        -re "(yes/no|continue connecting)" { send "yes\r"; exp_continue }
        -re "(U|u)sername:" { send "$user\r"; exp_continue }
        -re "(P|p)assword:" { send "$pass\r"; exp_continue }
        -re "Switch#" { }
        timeout { puts stderr "TIMEOUT during login to $host"; exit 1 }
        eof { puts stderr "EOF during login to $host"; exit 1 }
    }
}

proc quiet_exit {} {
    send "exit\r"
    expect {
        -re "Switch>" { send "exit\r"; exp_continue }
        eof { }
        timeout { }
    }
}

proc do_save {mode} {
    if { $mode eq "write-nosave" } {
        puts "Changes applied to running-config (NOT saved to flash)."
    } else {
        cmd "save" "Switch#"
        puts "Changes saved to flash."
    }
}

# =====================================================================
# Login
# =====================================================================
login $host $user $pass

set timeout 5
send "terminal length 0\r"
expect {
    -re "Switch\[>#\]" { }
    -re "Invalid|Unknown|error|Error" { expect -re "Switch\[>#\]" }
    timeout { puts "note: terminal length 0 gave no prompt; --More-- handler will cope." }
}
set timeout 30

# =====================================================================
# Read-only mode
# =====================================================================
if { $mode eq "read" } {
    cmd "show vlan static" "Switch#"
    cmd "show ip interface vlan$mgmt_vlan" "Switch#"
    cmd "show ip interface vlan1" "Switch#"
    cmd "show running-config" "Switch#"
    quiet_exit
    exit 0
}

# =====================================================================
# Configuration phases
# =====================================================================
cmd "configure" "config.*#"

# Phase 1 — VLAN entries
foreach vid {10 20 30 40 50} {
    send "vlan $vid\r"
    expect {
        -re "config-vlan.*#" { }
        -re "config.*#" { exp_continue }
        timeout { puts stderr "TIMEOUT on 'vlan $vid'"; exit 1 }
    }
    send "name $vlan_names($vid)\r"
    expect -re "config-vlan.*#"
    send "exit\r"
    expect -re "config.*#"
}

# Phase 2 — SFP+ uplink trunk (VLANs 10-50 tagged)
cmd "interface $uplink" "config-if.*#"
cmd "switchport mode hybrid" "config-if.*#"
foreach vid {10 20 30 40 50} {
    cmd "switchport hybrid allowed vlan add $vid tagged" "config-if.*#"
}
cmd "exit" "config.*#"

# Phase 3 — LAGs (empty by default)
foreach lagid [array names lag_vlan] {
    cmd "interface lag $lagid" "config-if.*#"
    cmd "switchport mode hybrid" "config-if.*#"
    cmd "switchport hybrid allowed vlan add $lag_vlan($lagid) untagged" "config-if.*#"
    cmd "exit" "config.*#"
    foreach p $lag_members($lagid) {
        cmd "interface $p" "config-if.*#"
        cmd "lag $lagid" "config-if.*#"
        cmd "exit" "config.*#"
    }
}

# Phase 4 — standalone access ports (TRUE hybrid untagged)
foreach vid {10 20 30 40 50} {
    if {![info exists vlan_ports($vid)]} { continue }
    foreach p $vlan_ports($vid) {
        cmd "interface $p" "config-if.*#"
        cmd "switchport mode hybrid" "config-if.*#"
        cmd "switchport hybrid allowed vlan add $vid untagged" "config-if.*#"
        cmd "exit" "config.*#"
    }
}

# Phase 4b — Terraform host port: VLAN 1 untagged + mgmt VLAN tagged
cmd "interface $host_port" "config-if.*#"
cmd "switchport mode hybrid" "config-if.*#"
soft_cmd "switchport hybrid allowed vlan add 1 untagged" "config-if.*#" ".*already.*|.*exist.*|.*Invalid.*"
soft_cmd "switchport hybrid allowed vlan add $mgmt_vlan tagged" "config-if.*#" ".*already.*|.*exist.*|.*Invalid.*"
cmd "exit" "config.*#"

# =====================================================================
# Phase 5 — bring mgmt VLAN SVI up via bootstrap IP
# =====================================================================
puts "==> Phase 5: bringing up interface vlan$mgmt_vlan via bootstrap IP $bootstrap_ip ..."
cmd "interface vlan$mgmt_vlan" "config-if.*#"
soft_cmd "ip address $bootstrap_ip $mgmt_mask" "config-if.*#" ".*already.*|.*exist.*|.*overlap.*"
cmd "exit" "config.*#"

if { $migrate_mgmt eq "true" } {
    puts "==> Phase 5b: moving mgmt IP $mgmt_ip from vlan1 to vlan$mgmt_vlan ..."
    cmd "interface vlan$mgmt_vlan" "config-if.*#"
    soft_cmd "ip address $mgmt_ip $mgmt_mask" "config-if.*#" ".*already.*|.*exist.*|.*overlap.*|.*does not exist.*"
    cmd "exit" "config.*#"

    cmd "interface vlan1" "config-if.*#"
    soft_cmd "no ip address" "config-if.*#" ".*does not exist.*|.*Invalid.*|.*Unknown.*"
    cmd "exit" "config.*#"
}

cmd "exit" "Switch#"

# =====================================================================
# Phase 6 — save; reconnect if the session dropped mid-migration.
# =====================================================================
if { [catch { cmd "show version" "Switch#" } err] } {
    puts "Session dropped after migration (expected). Reconnecting to $mgmt_ip ..."
    catch { close }
    after 3000

    set retries 0
    set connected 0
    while { $retries < 10 } {
        if { [catch { login $mgmt_ip $user $pass } err] } {
            puts "Reconnect attempt [expr {$retries+1}] failed."
            incr retries
            after 3000
        } else {
            set connected 1
            break
        }
    }
    if { !$connected } {
        puts stderr "ERROR: could not reconnect to $mgmt_ip after 10 attempts."
        puts stderr "The running-config was modified but not saved. Re-run after fixing host routing."
        exit 1
    }
    set timeout 5
    send "terminal length 0\r"
    expect {
        -re "Switch\[>#\]" { }
        timeout { }
    }
    set timeout 30
}

do_save $mode

# Remove bootstrap IP now that primary is established.
if { $migrate_mgmt eq "true" } {
    cmd "configure" "config.*#"
    cmd "interface vlan$mgmt_vlan" "config-if.*#"
    soft_cmd "no ip address $bootstrap_ip $mgmt_mask" "config-if.*#" ".*does not exist.*|.*Invalid.*|.*Unknown.*"
    cmd "exit" "config.*#"
    cmd "exit" "Switch#"
    if { $mode ne "write-nosave" } {
        cmd "save" "Switch#"
    }
}

quiet_exit
exit 0
INNER_EOF

      # ---------- dry-run branch ----------
      if [ "${var.dry_run}" = "true" ]; then
        echo "DRY RUN: read-only."
        create_host_vlan
        ip route add "${var.switch_host}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        ip route add "${var.bootstrap_ip}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        expect "$EXPECT_SCRIPT" read \
          "${var.switch_host}" "${var.switch_user}" \
          "$SWITCH_PASS" \
          "${var.uplink_port}" "$VN_STR" "$VP_STR" "$LAG_STR" \
          "${var.mgmt_vlan}" "${var.mgmt_ip}" "${var.mgmt_subnet_mask}" \
          "${var.migrate_mgmt_to_vlan10}" "${var.terraform_host_port}" "${var.bootstrap_ip}"
        exit 0
      fi

      # ---------- apply branch ----------
      MODE="write-save"
      if [ "${var.no_save_first}" = "true" ]; then MODE="write-nosave"; fi

      create_host_vlan

      SWITCH_PATH=""
      if ping -c1 -W1 "${var.switch_host}" >/dev/null 2>&1; then
        echo "Switch ${var.switch_host} reachable via default route (assume VLAN 1)."
        SWITCH_PATH="default"
      else
        echo "Default route cannot reach ${var.switch_host}; trying host VLAN sub-interface ..."
        ip route add "${var.switch_host}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        ip route add "${var.bootstrap_ip}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        if ping -c1 -W1 "${var.switch_host}" >/dev/null 2>&1; then
          echo "Switch ${var.switch_host} reachable via host VLAN interface."
          SWITCH_PATH="vlan10"
        else
          echo "ERROR: switch ${var.switch_host} unreachable via both default route and VLAN ${var.mgmt_vlan}." >&2
          echo "" >&2
          echo "Diagnostics:" >&2
          ip -br addr show "$HOST_VLAN_IFACE" >&2 || true
          echo "" >&2
          echo "Possible causes and fixes:" >&2
          echo "  1. The previous failed run moved the switch IP to VLAN 10 but" >&2
          echo "     did NOT configure MGI${var.terraform_host_port} as a hybrid port." >&2
          echo "     FIX: physically move the Terraform host cable to a port" >&2
          echo "     that was previously configured untagged in VLAN ${var.mgmt_vlan}" >&2
          echo "     (try MGI1, MGI4, MGI5, MGI6), then re-run this command." >&2
          echo "  2. Switch is at factory IP ${var.factory_ip}." >&2
          echo "     FIX: run ../horaco-switch-bootstrap first, or add" >&2
          echo "     -var switch_host=${var.factory_ip} on a host interface" >&2
          echo "     in 192.168.2.0/24." >&2
          echo "  3. Switch is on a different IP (e.g. 10.10.10.4 from the" >&2
          echo "     handoff's bootstrap). Try -var switch_host=10.10.10.4 ." >&2
          exit 1
        fi
      fi

      echo "APPLY: mode=$MODE uplink=${var.uplink_port} mgmt=vlan${var.mgmt_vlan}@${var.mgmt_ip} path=$SWITCH_PATH"

      ip route add "${var.switch_host}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
      ip route add "${var.bootstrap_ip}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true

      set +e
      expect "$EXPECT_SCRIPT" "$MODE" \
        "${var.switch_host}" "${var.switch_user}" \
        "$SWITCH_PASS" \
        "${var.uplink_port}" "$VN_STR" "$VP_STR" "$LAG_STR" \
        "${var.mgmt_vlan}" "${var.mgmt_ip}" "${var.mgmt_subnet_mask}" \
        "${var.migrate_mgmt_to_vlan10}" "${var.terraform_host_port}" "${var.bootstrap_ip}"
      apply_rc=$?
      set -e

      if ! ping -c1 -W1 "${var.switch_host}" >/dev/null 2>&1; then
        echo "✗ ${var.switch_host} no longer responds (expect rc=$apply_rc)." >&2
        ip -br addr show "$HOST_VLAN_IFACE" 2>/dev/null || true
        ip route show 2>/dev/null | grep -E "${var.switch_host}|${var.bootstrap_ip}" || true
        exit 1
      fi

      if [ "$apply_rc" -ne 0 ]; then
        echo "ERROR: expect exited $apply_rc, but ${var.switch_host} is still reachable." >&2
        exit 1
      fi

      echo "✓ Config applied; ${var.switch_host} still reachable on VLAN ${var.mgmt_vlan}."
    EOT
  }
}