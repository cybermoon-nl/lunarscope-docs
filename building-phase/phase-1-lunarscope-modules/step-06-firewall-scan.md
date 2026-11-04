# Step 6 — Second module: `firewall_scan`

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done

## Goal

Create `src/modules/firewall_scan.rs`: check whether UFW is active with
`systemctl is-active ufw` and return a HIGH finding if it is not.

## What was done

### Files

| File | Change |
|------|--------|
| `src/modules/firewall_scan.rs` | New — the `FirewallScan` module + unit tests |
| `src/modules/mod.rs` | Added `pub mod firewall_scan;` |

### Structure of the module

```rust
pub struct FirewallScan;

impl ScanModule for FirewallScan {
    fn name(&self) -> &str { "firewall_scan" }
    fn description(&self) -> &str { "Checks whether the UFW firewall is active" }
    fn run(&self) -> Vec<Finding> {
        let state = service_state();
        let conf = fs::read_to_string("/etc/ufw/ufw.conf").ok();
        vec![evaluate(state.as_deref().map_err(String::as_str), conf.as_deref())]
    }
}
```

| Function | Responsibility |
|----------|----------------|
| `service_state()` | Runs `systemctl is-active ufw` and returns what it prints (`active`, `inactive`, `failed`, …), or an error if systemctl can't be run |
| `conf_enabled(conf)` | Reads `ENABLED=yes\|no` from the contents of `/etc/ufw/ufw.conf` |
| `evaluate(state, conf)` | Pure function that turns both inputs into the finding |

As in `ssh_scan`, all the logic is in a pure function (`evaluate`). `run()`
only collects the system state, so every outcome can be unit tested without
needing a server with or without UFW.

### Findings produced

All outcomes use `check_name` = `firewall_ufw_active` and return exactly one
finding.

| Service state | `ufw.conf` | Severity | Description |
|---------------|------------|----------|-------------|
| `active` | `ENABLED=yes` or unreadable | Pass | UFW firewall is active |
| `active` | `ENABLED=no` | **High** | Service running but firewall disabled |
| anything else (`inactive`, `failed`, …) | — | **High** | Not active or not installed (includes the reported state) |
| systemctl can't be run | — | **Low** | Could not check the UFW status |

## Choices and justification

- **`systemctl is-active` instead of `ufw status`** — `ufw status` needs root,
  while the agent runs as the unprivileged `lunarscope` user (step 20).
  `systemctl is-active` and `/etc/ufw/ufw.conf` (mode `0644`) are both
  readable without privileges. (The SQ6 PoC used `ufw status`, which only
  works when the agent runs as root.)
- **The printed state is used, not the exit code** — `is-active` exits
  non-zero for every state except `active` (e.g. exit 4 for `inactive`).
  A non-zero exit is therefore not an error. The text it prints is used, so
  the actual state appears in the finding description.
- **Not installed counts as not active (High)** — systemctl reports
  `inactive` for a unit that doesn't exist. Both cases mean the server has
  no host firewall, so both are High, and the remediation covers installing.
- **Extra check on `ENABLED` in `ufw.conf`** — `ufw.service` is a oneshot
  unit with `RemainAfterExit=yes`. After `sudo ufw disable` the firewall
  rules are removed, but the unit can still report `active`. `ufw disable`
  does write `ENABLED=no` to `/etc/ufw/ufw.conf`, so the module checks that
  file too. Checking only `systemctl` would give a false Pass. If the file
  can't be read, the service state alone decides.
- **Remediation allows SSH before enabling** — enabling UFW on a remote
  server without `ufw allow OpenSSH` locks the admin out. Since the target
  users are SMB admins, the remediation lists the safe order.
- **Low when systemctl can't run** — same rule as `ssh_scan`: a check that
  can't be performed is reported, not hidden. Low, because it says nothing
  about the firewall itself.
- **Only UFW** — UFW is the default firewall front-end on Ubuntu 24.04, the
  target platform. Servers that use nftables/iptables directly or firewalld
  will get a High finding. This is an accepted limitation of the prototype,
  noted for later modules.

## Verification

Unit tests (see [testing.md](testing.md)) cover every row of the findings
table above, plus `conf_enabled` parsing and a run against the real system.

```text
$ cargo test
test result: ok. 26 passed; 0 failed

$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

Running the module on the development machine (Fedora, uses firewalld, no UFW
installed):

```json
{
  "check_name": "firewall_ufw_active",
  "severity": "High",
  "description": "UFW firewall is not active or not installed (systemctl reports 'inactive')",
  "remediation": "Install and enable UFW: 'sudo apt install ufw', 'sudo ufw allow OpenSSH', 'sudo ufw enable'"
}
```

## Next step

Step 7 — third module: `package_scan`.
