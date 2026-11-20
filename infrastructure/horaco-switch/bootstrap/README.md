# horaco-switch-bootstrap

One-shot recovery: take a factory-reset Horaco ZX-SWTG3624AS from
`192.168.2.1` to `10.10.10.3/24` and persist the change.

Run **only** after a pinhole reset. Idempotent — short-circuits if
`10.10.10.3` already responds.

## Prerequisites (after every factory reset)

1. Pinhole reset (~10 s). Switch boots at `192.168.2.1`, SSH off.
2. Laptop NIC → `192.168.2.100/24`, no gateway.
3. Browse `http://192.168.2.1` → **Security → Management Access →
   Management Service** → SSH **on** → **Apply**.
4. Do **not** change the IP in the web UI — it hangs. Bootstrap does it.

## Run

```bash
export TF_VAR_switch_password='admin'
tofu init
tofu apply
```

Expected final line: `✓ Configuration saved on 10.10.10.3`.

## After

Laptop NIC → DHCP. Verify:

```bash
ping 10.10.10.3
ssh -oHostKeyAlgorithms=+ssh-rsa admin@10.10.10.3 'show running-config'
```

Then proceed to `../horaco-switch-config`.