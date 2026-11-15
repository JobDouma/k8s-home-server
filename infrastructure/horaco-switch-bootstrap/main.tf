resource "null_resource" "switch_ip_config" {
  triggers = {
    switch_host   = var.switch_host
    switch_new_ip = var.switch_new_ip
    always_run    = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]

    command = <<-EOT
      set -e

      if [ -z "$${TF_VAR_switch_password:-}" ]; then
        echo "ERROR: TF_VAR_switch_password is not set in the shell." >&2
        echo "       export TF_VAR_switch_password='...' before running tofu apply." >&2
        exit 1
      fi

      # --- Gate 1: already at target IP? ------------------------------------
      if [ "${var.force_reconfigure}" != "true" ] \
         && ping -c1 -W1 "${var.switch_new_ip}" >/dev/null 2>&1; then
        echo "✓ Switch already reachable at ${var.switch_new_ip}; skipping configuration."
        exit 0
      fi

      # --- Gate 2: required tools -------------------------------------------
      for cmd in ping ssh expect; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
          echo "ERROR: '$cmd' not installed. In WSL: sudo apt update && sudo apt install -y $cmd" >&2
          exit 1
        fi
      done

      # --- Gate 3: variable sanity ------------------------------------------
      if [ "${var.switch_host}" = "${var.switch_new_ip}" ]; then
        echo "ERROR: switch_host and switch_new_ip must differ." >&2
        exit 1
      fi

      # --- Gate 4: current IP reachable? ------------------------------------
      if ! ping -c1 -W1 "${var.switch_host}" >/dev/null 2>&1; then
        echo "ERROR: ${var.switch_new_ip} is not reachable, and neither is ${var.switch_host}." >&2
        echo "       If the switch was recently moved to a different IP, set TF_VAR_switch_host to its current address." >&2
        exit 1
      fi

      # --- Gate 5: SSH port open on current IP? -----------------------------
      if ! timeout 3 bash -c "echo > /dev/tcp/${var.switch_host}/22" 2>/dev/null; then
        echo "ERROR: SSH (port 22) is not open on ${var.switch_host}." >&2
        echo "       Enable it in the web UI: Security > Management Access > Management Service." >&2
        exit 1
      fi

      # --- Shared expect script (mode: set-ip | save) -----------------------
      EXPECT_SCRIPT=$(mktemp)
      trap 'rm -f "$EXPECT_SCRIPT"' EXIT

      cat > "$EXPECT_SCRIPT" <<'INNER_EOF'
set timeout 20
log_user 1

set mode    [lindex $argv 0]
set host    [lindex $argv 1]
set user    [lindex $argv 2]
set pass    [lindex $argv 3]
set newip   [lindex $argv 4]
set newbits [lindex $argv 5]
set vlan    [lindex $argv 6]

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
    timeout { puts stderr "TIMEOUT during login"; exit 1 }
    eof { puts stderr "EOF during login"; exit 1 }
}

if { $mode eq "set-ip" } {
    send "configure\r"
    expect -re "config.*#"
    send "interface $vlan\r"
    expect -re "config.*#"
    send "ip address $newip/$newbits\r"
    # The switch drops the SSH session immediately after changing its own IP.
    # Accept prompt, eof, or a short timeout — all three mean "move on".
    set timeout 8
    expect {
        -re "config.*#" { }
        eof { }
        timeout { }
    }
    catch { close }
    catch { wait }
    exit 0
} else {
    # save mode — reconnect to the new IP and persist the running-config
    send "save\r"
    expect -re "Switch#"
    send "exit\r"
    expect {
        -re "Switch>" { send "exit\r"; exp_continue }
        eof { }
        timeout { }
    }
    exit 0
}
INNER_EOF

      # --- Phase 1: set the new IP on the old address -----------------------
      echo "Phase 1: setting IP ${var.switch_host} -> ${var.switch_new_ip}/${var.switch_subnet_bits}"
      set +e
      expect "$EXPECT_SCRIPT" set-ip \
        "${var.switch_host}" \
        "${var.switch_user}" \
        "$${TF_VAR_switch_password}" \
        "${var.switch_new_ip}" \
        "${var.switch_subnet_bits}" \
        "${var.vlan_interface}"
      phase1_rc=$?
      set -e

      # Non-zero exit from phase 1 is not fatal: the switch may have closed the
      # session mid-command. The ping below is the real source of truth.

      # --- Wait for the switch to appear on the new IP ----------------------
      echo "Waiting for ${var.switch_new_ip} to respond..."
      new_ip_up=""
      for i in $(seq 1 20); do
        if ping -c1 -W1 "${var.switch_new_ip}" >/dev/null 2>&1; then
          new_ip_up="yes"
          break
        fi
        sleep 1
      done

      if [ -z "$new_ip_up" ]; then
        echo "✗ ${var.switch_new_ip} did not come up after 20s." >&2
        echo "  Phase 1 exit code: $phase1_rc" >&2
        echo "  The IP change did not take effect. Check the switch's current address." >&2
        exit 1
      fi
      echo "✓ ${var.switch_new_ip} is responding"

      # --- Phase 2: reconnect to the new IP and save ------------------------
      echo "Phase 2: saving configuration on ${var.switch_new_ip}"
      set +e
      expect "$EXPECT_SCRIPT" save \
        "${var.switch_new_ip}" \
        "${var.switch_user}" \
        "$${TF_VAR_switch_password}" \
        "" "" ""
      phase2_rc=$?
      set -e

      if [ "$phase2_rc" -ne 0 ]; then
        echo "✗ Could not save configuration on ${var.switch_new_ip} (exit $phase2_rc)." >&2
        echo "  The IP is live in running-config but WILL revert on reboot." >&2
        echo "  Reconnect manually: ssh -tt -oHostKeyAlgorithms=+ssh-rsa ${var.switch_user}@${var.switch_new_ip}" >&2
        echo "  Then run: save" >&2
        exit 1
      fi

      echo "✓ Configuration saved on ${var.switch_new_ip}"
    EOT
  }
}