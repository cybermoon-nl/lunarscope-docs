# Step 13 — Example `config.toml`

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

## Goal

An example `config.toml` with the three modules enabled and a placeholder
`master_url`.

## What was done

`config.toml` in the repo root:

```toml
# Lunarscope agent configuration.
# Installed as /etc/lunarscope/config.toml (owner root:lunarscope, mode 640),
# because it contains the API key.

# UUID of this agent, as registered on the master node.
agent_id = "00000000-0000-0000-0000-000000000000"

# Pre-shared API key from the master's registration endpoint.
api_key = "replace-with-api-key-from-master"

# Base URL of the master node. Must be https; plain http is only accepted
# for localhost during development.
master_url = "https://lunarscope.example.com"

# Seconds between two scan cycles (minimum 10).
interval_seconds = 3600

[modules]
# Scan modules to run. Available: ssh_scan, firewall_scan, package_scan.
enabled = ["ssh_scan", "firewall_scan", "package_scan"]
```

## Choices and justification

- **Placeholders that are obviously not real** — an all-zero UUID and
  `replace-with-api-key-from-master`. The file is committed to git, so it must
  never contain a real key (gitleaks will scan the history in phase 4).
- **`https://lunarscope.example.com`** — `example.com` is reserved for
  documentation (RFC 2606), so the placeholder can never point at someone
  else's server by accident.
- **Interval 3600 s** — the hourly interval from the architecture document.
  Package lists only refresh daily (`apt-daily.timer`), so scanning much more
  often adds load without adding information.
- **Comments in the file** — admins at SMBs install this by hand. The comments
  explain the file permissions, the https rule, the minimum interval and the
  available module names in the place where they are needed.

## Checks

- `example_config_in_repo_is_valid` (unit test, step 12) loads this exact file
  with `include_str!("../config.toml")` and checks that it validates and enables
  `ssh_scan`, `firewall_scan`, `package_scan`. If someone breaks the example,
  the tests fail.
- The file was used as the base for the systemd installation test (step 20),
  with only the four values replaced.

## Next step

Step 14 — module registry.
