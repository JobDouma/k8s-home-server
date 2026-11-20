# horaco-switch-config

Applies VLAN config (trunk on SFP+, PVIDs on copper) to the Horaco
ZX-SWTG3624AS at `10.10.10.3`. Assumes
`../horaco-switch-bootstrap` has already run.

## 🛡️ Three-mode safety

| Mode | Variables | Behaviour |
|---|---|---|
| Dry run (default) | `dry_run=true` | Runs `show vlan static` + `show running-config`. Zero changes. |
| Apply unsaved | `dry_run=false no_save_first=true` | Changes running-config, does **not** save. Post-check pings the switch. Power-cycle reverts on failure. |
| Apply + save | `dry_run=false no_save_first=false` | Changes and saves. Only after unsaved proved safe. |

## Rollout

```bash
export TF_VAR_switch_password='admin'
sudo apt install -y jq expect      # if not present

tofu init
tofu apply -var dry_run=true                      # 1. inspect
tofu apply -var dry_run=false -var no_save_first=true   # 2. apply unsaved
# verify: ssh -tt -oHostKeyAlgorithms=+ssh-rsa admin@10.10.10.3 'show vlan static'
# verify: plug laptop into mgi5 -> DHCP 10.10.30.x
tofu apply -var dry_run=false -var no_save_first=false  # 3. save
# 4. reboot test: ssh admin@10.10.10.3 -> Switch# reboot -> ping 10.10.10.3
```

## ⚠️ Verify trunk syntax before `dry_run=false`

`config vlan <vid> add port <port> tagged` is the Realtek default but
your firmware may differ. Check manually once:

```bash
ssh -tt -oHostKeyAlgorithms=+ssh-rsa admin@10.10.10.3
Switch# configure
Switch(config)# config ?
Switch(config)# vlan 10
Switch(config-vlan)# ?
```

If `add port` is rejected, try `member <port> tagged` inside
`vlan <vid>` mode, or `ports add <port> tagged`. Adjust Phase 2 in
`main.tf` accordingly.

## What gets configured

- **Trunk on `te1`**: VLAN 1 (mgmt, tagged) + VLANs 10, 20, 30, 40, 50 (tagged)
- **Access ports** (from `vlan_port_map`):
  - `mgi1`–`mgi2` → MGMT (10)
  - `mgi3`–`mgi4` → IOT (20)
  - `mgi5`–`mgi8` → HOME (30)
  - `mgi9` → GUEST (40)
  - `mgi10`–`mgi11` → CAMERA (50)

## Management-IP safety

`10.10.10.3` lives on `interface vlan1`. The very first trunk command
adds **VLAN 1 tagged** on `te1` before touching any other VLAN, so
OPNsense can always route back. Moving mgmt to VLAN 10 later is a
separate two-step change (add secondary IP on `interface vlan10`,
verify, remove from `vlan1`).

## Failure recovery

| Where it fails | What to do |
|---|---|
| `dry_run` cannot reach `10.10.10.3`, but `192.168.2.1` responds | Run `../horaco-switch-bootstrap` |
| Apply-unsaved breaks `10.10.10.3` | Power-cycle switch → reverts to last saved config |
| Apply-save breaks `10.10.10.3` | Console cable + restore from `show running-config` backup |