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
    host_vlan_ip         = var.host_vlan_ip
    host_vlan_prefix     = var.host_vlan_prefix
    migrate_mgmt_to_vlan = var.migrate_mgmt_to_vlan10
    dry_run              = var.dry_run
    save_after_verify    = var.save_after_verify
    always_run           = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]

    environment = {
      SWITCH_PASS = var.switch_password
    }

    command = <<-EOT
      set -e

      if [ -z "$SWITCH_PASS" ]; then
        echo "ERROR: switch_password is empty. Set TF_VAR_switch_password." >&2
        exit 1
      fi
      export SWITCH_PASS

      if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: must run as root. Use: sudo -E tofu apply ..." >&2
        exit 1
      fi

      for c in ping ssh expect jq ip seq; do
        command -v "$c" >/dev/null 2>&1 || {
          echo "ERROR: '$c' not installed." >&2; exit 1; }
      done

      # ---------- detect host interface ----------
      HOST_IFACE=$(ip route get "${var.switch_host}" 2>/dev/null | grep -oP 'dev \K\S+' | head -1 || true)
      if [ -z "$HOST_IFACE" ]; then
        HOST_IFACE=$(ip route | awk '/default/ {print $5; exit}')
      fi
      if [ -z "$HOST_IFACE" ]; then
        echo "ERROR: could not detect host network interface." >&2
        exit 1
      fi
      echo "Detected host interface: $HOST_IFACE"

      HOST_VLAN_IFACE="$HOST_IFACE.${var.mgmt_vlan}"

      # ---------- host VLAN helpers (tolerant; usually fails on WSL2) ----------
      create_host_vlan() {
        if ip link show "$HOST_VLAN_IFACE" >/dev/null 2>&1; then
          echo "Host VLAN interface $HOST_VLAN_IFACE exists; reusing."
        else
          echo "Creating host VLAN interface $HOST_VLAN_IFACE (VLAN ${var.mgmt_vlan}) ..."
          if ! ip link add link "$HOST_IFACE" name "$HOST_VLAN_IFACE" type vlan id "${var.mgmt_vlan}" 2>/dev/null; then
            echo "WARNING: could not create VLAN interface (normal on WSL2). Continuing." >&2
            return 0
          fi
        fi
        ip addr add "${var.host_vlan_ip}/${var.host_vlan_prefix}" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        ip link set dev "$HOST_VLAN_IFACE" up 2>/dev/null || true
      }

      destroy_host_vlan() {
        ip route del "${var.switch_host}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        ip route del "${var.mgmt_ip}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        if ip link show "$HOST_VLAN_IFACE" >/dev/null 2>&1; then
          ip link del "$HOST_VLAN_IFACE" 2>/dev/null || true
        fi
      }

      # Returns 0 if switch_host answers (default route or host VLAN iface)
      reach_switch() {
        if ping -c1 -W1 "${var.switch_host}" >/dev/null 2>&1; then
          echo "Switch ${var.switch_host} reachable via default route."
          return 0
        fi
        echo "Not reachable via default route; trying host VLAN sub-interface ..."
        create_host_vlan
        ip route add "${var.switch_host}/32" dev "$HOST_VLAN_IFACE" 2>/dev/null || true
        ping -c1 -W1 "${var.switch_host}" >/dev/null 2>&1
      }

      # Wait up to ~60s for an IP to answer
      wait_for_ip() {
        for i in $(seq 1 20); do
          if ping -c1 -W1 "$1" >/dev/null 2>&1; then return 0; fi
          sleep 3
        done
        return 1
      }

      # ---------- payloads ----------
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
set uplink          [lindex $argv 3]
set vlan_names_str  [lindex $argv 4]
set vlan_ports_str  [lindex $argv 5]
set lag_str         [lindex $argv 6]
set mgmt_vlan       [lindex $argv 7]
set mgmt_ip         [lindex $argv 8]
set mgmt_mask       [lindex $argv 9]
set migrate_mgmt    [lindex $argv 10]
set pass            $env(SWITCH_PASS)

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
        -re $err_re {
            puts "WARN: '$text' was rejected by the switch (ignored)."
            expect -re $prompt
        }
        -re $prompt { }
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
        -oConnectTimeout=5 \
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

proc disable_paging {} {
    set timeout 5
    send "terminal length 0\r"
    expect {
        -re "Switch\[>#\]" { }
        timeout { }
    }
    set timeout 30
}

# ---------- login ----------
login $host $user $pass
disable_paging

# ---------- read-only ----------
if { $mode eq "read" } {
    cmd "show vlan static" "Switch#"
    cmd "show ip interface vlan$mgmt_vlan" "Switch#"
    cmd "show ip interface vlan1" "Switch#"
    cmd "show running-config" "Switch#"
    quiet_exit
    exit 0
}

# ---------- save-only (run after reachability verified) ----------
if { $mode eq "save" } {
    cmd "save" "Switch#"
    puts "Changes saved to flash."
    quiet_exit
    exit 0
}

# ---------- apply ----------
cmd "configure" "config.*#"

# Phase 1 - VLAN entries
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

# Phase 2 - uplink trunk (VLANs 10-50 tagged)
cmd "interface $uplink" "config-if.*#"
cmd "switchport mode hybrid" "config-if.*#"
foreach vid {10 20 30 40 50} {
    cmd "switchport hybrid allowed vlan add $vid tagged" "config-if.*#"
}
cmd "exit" "config.*#"

# Phase 3 - LAGs (empty by default)
foreach lagid [array names lag_vlan] {
    cmd "interface lag $lagid" "config-if.*#"
    cmd "switchport mode hybrid" "config-if.*#"
    cmd "switchport hybrid allowed vlan add $lag_vlan($lagid) untagged" "config-if.*#"
    soft_cmd "switchport hybrid pvid $lag_vlan($lagid)" "config-if.*#" "Invalid|Unknown|Incomplete"
    cmd "exit" "config.*#"
    foreach p $lag_members($lagid) {
        cmd "interface $p" "config-if.*#"
        cmd "lag $lagid" "config-if.*#"
        cmd "exit" "config.*#"
    }
}

# Phase 4 - cutover batch.
# Access ports (untagged + PVID) and the SVI move are sent in ONE write so the
# switch already holds every command when the SSH session drops.
set batch {}
foreach vid {10 20 30 40 50} {
    if {![info exists vlan_ports($vid)]} { continue }
    foreach p $vlan_ports($vid) {
        lappend batch "interface $p"
        lappend batch "switchport mode hybrid"
        lappend batch "switchport hybrid allowed vlan add $vid untagged"
        lappend batch "switchport hybrid pvid $vid"
        lappend batch "exit"
    }
}

if { $migrate_mgmt eq "true" } {
    # Remove the IP from vlan1 FIRST so the new SVI IP does not overlap.
    lappend batch "interface vlan1"
    lappend batch "no ip address"
    lappend batch "exit"
    lappend batch "interface vlan$mgmt_vlan"
    set prefix 0
    foreach o [split $mgmt_mask "."] {
        set n $o
        while { $n > 0 } { incr prefix [expr {$n & 1}]; set n [expr {$n >> 1}] }
    }
    lappend batch "ip address $mgmt_ip/$prefix"
    lappend batch "exit"
}
lappend batch "end"

puts "==> Phase 4: sending cutover batch ([llength $batch] commands) ..."
send "[join $batch "\r"]\r"
after 4000

# Drop the (probably dead) session and reconnect to verify.
catch { close }
catch { wait }

set target $host
if { $migrate_mgmt eq "true" } { set target $mgmt_ip }

set retries 0
set connected 0
while { $retries < 15 } {
    if { [catch { login $target $user $pass } err] } {
        puts "Reconnect attempt [expr {$retries+1}] to $target failed."
        incr retries
        after 3000
    } else {
        set connected 1
        break
    }
}
if { !$connected } {
    puts stderr "ERROR: could not reconnect to $target after 15 attempts."
    puts stderr "Config is in running-config ONLY (not saved). Power-cycle the switch to roll back."
    exit 1
}
disable_paging

cmd "show ip interface vlan$mgmt_vlan" "Switch#"
cmd "show vlan static" "Switch#"
puts "Changes applied to running-config (NOT saved to flash)."
quiet_exit
exit 0
INNER_EOF

      # ---------- dry-run ----------
      if [ "${var.dry_run}" = "true" ]; then
        echo "DRY RUN: read-only."
        if ! reach_switch; then
          echo "ERROR: switch ${var.switch_host} unreachable." >&2
          echo "FIX: set a static IP in the switch's subnet on your Windows adapter (wired to a mgi1-mgi8 port), then re-run." >&2
          exit 1
        fi
        expect "$EXPECT_SCRIPT" read \
          "${var.switch_host}" "${var.switch_user}" \
          "${var.uplink_port}" "$VN_STR" "$VP_STR" "$LAG_STR" \
          "${var.mgmt_vlan}" "${var.mgmt_ip}" "${var.mgmt_subnet_mask}" \
          "${var.migrate_mgmt_to_vlan10}"
        exit 0
      fi

      # ---------- apply ----------
      if ! reach_switch; then
        echo "ERROR: switch ${var.switch_host} unreachable via default route and VLAN ${var.mgmt_vlan}." >&2
        echo "FIX: set a static IP in the switch's subnet on your Windows adapter, plug into a copper port, then re-run." >&2
        echo "Diagnostics:" >&2
        ip -br addr show "$HOST_VLAN_IFACE" >&2 || true
        exit 1
      fi

      echo "APPLY: uplink=${var.uplink_port} mgmt=vlan${var.mgmt_vlan}@${var.mgmt_ip} migrate=${var.migrate_mgmt_to_vlan10}"

      set +e
      expect "$EXPECT_SCRIPT" apply \
        "${var.switch_host}" "${var.switch_user}" \
        "${var.uplink_port}" "$VN_STR" "$VP_STR" "$LAG_STR" \
        "${var.mgmt_vlan}" "${var.mgmt_ip}" "${var.mgmt_subnet_mask}" \
        "${var.migrate_mgmt_to_vlan10}"
      apply_rc=$?
      set -e

      if [ "$apply_rc" -ne 0 ]; then
        echo "ERROR: expect exited $apply_rc. Config was NOT saved; power-cycle the switch to roll back." >&2
        exit 1
      fi

      if ! wait_for_ip "${var.mgmt_ip}"; then
        echo "✗ ${var.mgmt_ip} does not respond after apply. NOT saved; power-cycle the switch to roll back." >&2
        exit 1
      fi

      echo "✓ Config applied; ${var.mgmt_ip} reachable."

      if [ "${var.save_after_verify}" = "true" ]; then
        echo "Saving to flash ..."
        expect "$EXPECT_SCRIPT" save \
          "${var.mgmt_ip}" "${var.switch_user}" \
          "${var.uplink_port}" "$VN_STR" "$VP_STR" "$LAG_STR" \
          "${var.mgmt_vlan}" "${var.mgmt_ip}" "${var.mgmt_subnet_mask}" \
          "${var.migrate_mgmt_to_vlan10}"
        echo "✓ Saved."
      else
        echo "NOT saved (save_after_verify=false). Re-run with -var save_after_verify=true once happy."
      fi
    EOT
  }
}