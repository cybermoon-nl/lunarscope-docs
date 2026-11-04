# Step 14 — Module registry

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

## Goal

A function `get_enabled_modules(config) -> Vec<Box<dyn ScanModule>>` in
`src/main.rs` that creates the modules listed in `modules.enabled`.

## What was done

```rust
fn get_enabled_modules(config: &Config) -> Result<Vec<Box<dyn ScanModule>>, String> {
    let mut available = all_modules();
    let mut enabled: Vec<Box<dyn ScanModule>> = Vec::new();
    let mut unknown = Vec::new();

    for name in &config.modules.enabled {
        if enabled.iter().any(|m| m.name() == name) {
            eprintln!("warning: module '{name}' is listed more than once in modules.enabled");
        } else if let Some(pos) = available.iter().position(|m| m.name() == name) {
            enabled.push(available.remove(pos));
        } else {
            unknown.push(name.as_str());
        }
    }

    if !unknown.is_empty() {
        // error lists the unknown names and the available ones
    }
    Ok(enabled)
}
```

## Choices and justification

- **Built on `lunarscope_modules::all_modules()`** (added in step 8). The agent
  doesn't name any concrete module type, so a new module in the library
  becomes usable with only a library version bump and a config change. That
  is the goal of the scan-module ADR.
- **Returns `Result` instead of a plain `Vec`** (a small deviation from the
  guide's signature). An unknown name, e.g. `"ssh-scan"` instead of
  `"ssh_scan"`, would otherwise silently disable that check, and the admin
  would believe the server is being checked. Now the agent refuses to start
  and prints:
  `unknown module(s) in modules.enabled: ssh-scan; available: ssh_scan, firewall_scan, package_scan`.
- **Config order is kept** — modules run (and their findings are sent) in the
  order the admin wrote them.
- **A duplicate name runs once**, with a warning. Running a module twice would
  send duplicate findings to the master.

## Checks — unit tests (`src/main.rs`)

| Test | Checks |
|------|--------|
| `enabled_modules_follow_config_order` | `["package_scan", "ssh_scan"]` → that order |
| `all_three_modules_can_be_enabled` | All three names are known to the registry |
| `unknown_module_is_an_error` | `"ssh-scan"`, `"cron_scan"` → error listing both and the available names |
| `duplicate_module_runs_once` | `["ssh_scan", "ssh_scan"]` → one module |

Mutation check: skipping the unknown-name error (`if false && …`) →
`unknown_module_is_an_error` fails.

## Next step

Step 15 — scan loop.
