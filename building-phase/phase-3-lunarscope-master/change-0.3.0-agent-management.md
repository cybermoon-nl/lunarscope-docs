# Change 0.3.0 — new GUI, agent management from the master, rule scans

**Repos:** `lunarscope-agent` (→ **0.3.0**), `lunarscope-master` (→ **0.3.0**)
**Date:** 2026-11-16
**Status:** Done — code and checks ready; commit + tag by hand

Agent 0.2.0 ([daily scan time](../phase-2-lunarscope-agent/change-0.2.0-daily-scan-time.md))
and master 0.2.0 ([dashboard login](change-0.2.0-dashboard-login.md)) were never
committed. Everything goes out together as **0.3.0** in both repos; those
two files still describe their part.

## Why

1. **A new look.** The dashboard takes over the design of the reference GUI
   on `http://192.168.6.151` (dark theme, sidebar, tiles, findings table
   with details panel, agent cards, weekly report).
2. **Manage agents from the master.** Switch scans on and off per agent,
   and set the scan time, **without reinstalling the agent**.
3. **Install script.** "Add agent" on the master gives a one-line command
   that installs the agent on a new server with the chosen scans.
4. **New scans without reinstalling.** A scan made on the master reaches
   the agents by itself.

## Decisions (made with the user)

| Question | Choice | Why |
|----------|--------|-----|
| How much of the reference GUI | The look, plus "Since previous scan", an EN/NL switch and the Report page. Without "Trigger scan" and certificate/domain expiry | No data for certificate expiry; triggering a scan needs a command channel to the agent |
| How new scans reach agents | **Rule scans as data**: a scan is a list of checks of six fixed test types, written in TOML on the master and sent as JSON | Agents never receive program code. A master that is broken into can change *what is checked*, but can't make every server run a command. Rejected: a signed agent self-update (any code possible, but every new scan needs a build and release) |
| Fonts | System fonts (Inter if installed) | The reference loads Inter from Google Fonts; the dashboard must work without internet and not tell Google who uses it (existing test) |

## How it works

```text
            dashboard (admin)                         agent (every server)
  Scans:  write rule scan (TOML) ──▶ scans table ──┐
  Agents: switch scan on/off,        agent_scans,  │   GET /api/agent-config (API key)
          scan time                  agents.scan_time,  at startup and every 5 min
                                     config_version +1 ─▶ {version, scan_time, modules, rule_scans}
                                                          version changed? ─▶ scan now
  Add agent ─▶ agent + install link ─▶ GET /install/{token}: script with new API key (once, 1 h)
                                       GET /downloads/lunarscope-agent: the binary (SHA-256 checked)
```

### Agent (0.3.0)

| File | Change |
|------|--------|
| `config.toml`, `src/config.rs` | Only `agent_id`, `api_key`, `master_url`. `scan_time` and `[modules]` are gone from the file and refused if present (an old config must be cleaned up, not half-used). `ScanTime` stays, now read from the master's JSON |
| `src/remote.rs` (new) | `RemoteConfig` (`version`, `scan_time`, `modules`, `rule_scans`) and `modules_for()`: built-in modules and rule scans by name, in the master's order. Unknown names are skipped with a warning, duplicates run once |
| `src/rules.rs` (new) | Rule engine: `RuleScan` implements `ScanModule`, so it runs like a built-in module. Test types: `file_exists`, `file_contains`, `config_value` (sshd_config style), `file_mode_max`, `service_active` (`systemctl is-active`), `package_installed` (`dpkg-query`). `expect = false` turns the first, second, fifth and sixth around. Pass → `Pass`, fail → the check's severity (`Pass` not allowed there), test not possible → `Low` with the reason. Paths must be absolute without `..`; service/package names only `[A-Za-z0-9@._+:-]` and no leading `-` (they go to a command as one argument); files are read up to 1 MiB |
| `src/sender.rs` | `fetch_config()`: `GET /api/agent-config` with the API key, clear errors for 401 / other status / bad JSON / network, at most 1 MiB |
| `src/main.rs` | Startup: fetch config (retry every 60 s until the master answers). Scan at startup, then daily at `scan_time`. While waiting, ask the master every **5 minutes** (`CONFIG_POLL_SECONDS`); a new `version` → log "new configuration … scanning now", scan right away with it, then wait for `scan_time` again. Master unreachable during a poll → keep the old config. `--once` fetches the config once |

### Master (0.3.0)

| Part | Change |
|------|--------|
| `migrations/0003_agent_management.sql` | `agents` + `scan_time` (default `02:00`), `config_version`, `checked_in`. New tables `scans` (built-in rows for ssh/firewall/package + rule scans with source and JSON), `agent_scans` (on per agent), `install_tokens` (SHA-256 of the token, agent, expiry). Trigger: a new agent gets all built-in scans. Existing agents keep the three built-in scans. `latest_results` + `previous_severity`, `since` (back-filled so old results don't count as changes) |
| `src/db/queries.rs` | `insert_scan_result` keeps `previous_severity`/`since` when the severity changes. Dashboard queries hide results of scans that are **switched off** for the agent (unknown scan types stay visible). New: `findings` (with filters), `changes`, `agent_config`, scans, toggles, scan time, delete agent, `create_agent`, `use_install_token` (deletes the link and sets the new key hash in one transaction) |
| `src/rule_scans.rs` (new) | TOML parsing and checks (same test types as the agent, `deny_unknown_fields`, no `command` type, names, paths, modes, sizes); `EXAMPLE` for the editor |
| `src/routes/api.rs` | `GET /api/agent-config` (API key) |
| `src/routes/agents.rs` (new) | `/agents` cards (counts, bar, status, last seen, check-in, switches, scan time, delete, "View findings"), `/agents/new` + `POST /agents` (install command page) |
| `src/routes/install.rs` (new) | `GET /install/{token}`: bash script with the agent's new API key; only works once and for 1 h; 503 (link kept) without `--agent-binary`. `GET /downloads/lunarscope-agent`. URL from `--public-url` or the Host header (checked so it can't break out of the script's quotes) |
| `src/routes/scans.rs`, `report.rs` (new) | Scans list, rule scan editor (save = new or replace by name; error → editor again with the reason), delete. Report: risk score `100 − 20·C − 8·H − 3·M − L` (min 0), gauge, per server worst first, Critical/High with remediation |
| `src/routes/dashboard.rs`, `server.rs` | New layout: tiles, since previous scan, filters `?severity=` `?server=` (HTMX, refresh keeps them), shared findings table with details panel |
| `src/i18n.rs` (new) | 112 texts in one table (key, EN, NL); language cookie, `GET /lang/{en,nl}` back to the page it came from (only a local path, no open redirect) |
| `templates/*`, `static/app.js` | Reference design in `base.html`; new pages; `app.js` (78 lines): details panel, delete confirmation, copy button, only `textContent` |
| `src/main.rs` | `--agent-binary <path>` (read once, must be an ELF file, SHA-256 logged), `--public-url <url>` (scheme + host + port only) |
| `install/lunarscope-agent.service` | Copy of the agent's unit for the install script |
| `Cargo.toml` | `toml` 1.1.8 (same version as the agent) |

All dashboard pages (also Agents, Scans, Report and their forms) are behind
the login from 0.2.0. Forms are protected against cross-site posts by the
`SameSite=Strict` session cookie. `/install/…`, `/downloads/…` and the API
need no login.

## Rule scan example

```toml
name = "baseline_scan"
description = "Basic hardening checks"

[[check]]
check_name = "shadow_permissions"
severity = "High"
description = "/etc/shadow is not readable by other users (mode 640 or stricter)"
remediation = "Run: sudo chmod 640 /etc/shadow"
test = { type = "file_mode_max", path = "/etc/shadow", mode = "640" }

[[check]]
check_name = "telnetd_absent"
severity = "Critical"
description = "telnetd is not installed"
remediation = "Run: sudo apt purge telnetd"
test = { type = "package_installed", package = "telnetd", expect = false }
```

The agent reports e.g. `OK: telnetd is not installed` (Pass) or
`Failed: curl is not installed (curl is installed)` (the check's severity).

## Setting up (master server)

```bash
# Copy the agent binary next to the master and restart it with:
--agent-binary /usr/local/share/lunarscope/lunarscope-agent --public-url https://lunarscope.cybermoon.nl
```

Then **Agents → Add agent**, pick scans, and on the new server run the shown
command (`curl -fsSL https://…/install/<token> | sudo bash`).

**Existing agents (0.1.x/0.2.x):** their `config.toml` must lose
`interval_seconds` / `scan_time` / `[modules]` (the agent refuses to start
with them and names the key), and they need the 0.3.0 binary. Simplest:
"Add agent" and run the install command again (old agent row can be deleted).

## Tests

| Repo | Before | Now | New |
|------|------:|----:|-----|
| agent | 42 | **58** | `rules.rs` 11, `remote.rs` 7, `fetch_config` 2; scan-time tests now parse `ScanTime` directly; old-key test |
| master | 158 | **215** | `rule_scans` 7, `i18n` 4, `agents` 12, `install` 5, `scans` 5, `report` 3, `api` agent config 7, `db` 6 (migration 3, trigger, constraints), `dashboard` 6 (filters, tiles, changes, since, switched-off scans, URLs), `main` 1; templates tests rewritten (15) |

Highlights:

- The install flow end to end through the router: form → install page →
  script contains this agent's new key (its hash is stored) → second use 404;
  expired links refused and cleaned up; without binary 503 and the link stays.
- The generated script passes `bash -n`.
- Every page renders in **EN and NL** as a full document, without template
  syntax left, and loads nothing from other hosts.
- Agent data is escaped also inside `data-*` attributes of the details panel.
- `agent_config`: each agent gets only its own scans; saving a rule scan raises
  the version only of agents that use it; built-in scans can't be replaced.

### Checks

| Check | Agent | Master |
|-------|-------|--------|
| `cargo test --locked` | ✅ 58 | ✅ 215 |
| `cargo clippy --all-targets --all-features --locked -- -D warnings` | ✅ | ✅ |
| `cargo fmt --check` | ✅ | ✅ |
| `cargo build --release --locked` | ✅ 3,297,608 bytes | ✅ 9,507,584 bytes |

rustc 1.99.1, Fedora.

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| Switched-off scans not hidden | `results_of_a_switched_off_scan_are_hidden_until_it_is_on_again` |
| Toggle doesn't raise `config_version` | 3 tests (`switching_a_scan_raises_the_config_version`, …) |
| Install link not single-use | `adding_an_agent_gives_a_one_time_install_script` |
| Script skips the SHA-256 check | `script_checks_the_download_and_installs_the_unit` |
| `--public-url` allows quotes | `public_url_check`, `agent_binary_and_public_url_options` |
| Rule paths not checked (master) | `bad_values_are_refused_with_a_reason` |
| "Since previous scan" ignores `since` | `since_previous_scan_lists_resolved_and_new_checks` |
| Config contains other agents' scans | `each_agent_gets_only_its_own_scans` (added after the first run missed it) |
| `/report` route missing | 3 tests |
| Language switch allows `//evil.com` | `only_local_paths_are_used_from_the_referer` |
| `since` not moved on a change | 2 tests |
| Unknown scans from a tampered form kept | 3 tests |
| Agent: option-like names (`--now`) allowed | `names_for_commands_are_checked` |
| Agent: relative / `..` paths allowed | `relative_and_dotdot_paths_are_refused` |
| Agent: High mapped to Low | 4 tests |
| Agent: `expect = false` ignored | 2 tests |
| Agent: rule scan listed twice runs twice | `a_rule_scan_listed_twice_runs_once` (added after the first run missed it) |

All 17 caught. Two needed a new test first (marked).

Two things went wrong while checking and were fixed: the first mutation
batch didn't run (zsh doesn't split a command stored in a variable), and the
restore step gave files back their old timestamp, so cargo reused a mutated
build until the sources were touched. The mutation script now updates the
timestamp; the final results above come from a clean rebuild.

## End-to-end test

Release builds; master on `127.0.0.1:3030` with the demo database from
0.2.0 (copy kept as `master-v0.2.0-backup.db`), `--password-file`,
`--admin-token-file` and `--agent-binary`.

1. **Migration 3 on real data**: start log `lunarscope-master 0.3.0: … 2
   registered agent(s), … dashboard login enabled, agent binary sha256
   514f326ca914`; `_sqlx_migrations` 1, 2, 3; both old agents got
   `ssh_scan, firewall_scan, package_scan`; 8 of 8 latest results
   back-filled.
2. **GUI** (built-in browser): login page, dashboard (tiles, since previous
   scan, findings), Agents cards, Scans — all in the reference design.
3. **Rule scan through the GUI**: `baseline_scan` (3 checks) saved → listed
   as "Rule scan, 3 checks, 0 agents".
4. **Add agent** `ubuntu-test` with the built-in scans + `baseline_scan` →
   install page with
   `curl -fsSL http://127.0.0.1:3030/install/<64 hex> | sudo bash`, valid
   for 1 hour.
5. **Install** in a clean `ubuntu:24.04` container (host network, curl
   installed, run as root):

   ```text
   Installing the Lunarscope agent for ubuntu-test
   Installed, but systemd is not running here. Start the agent with:
     /usr/local/bin/lunarscope-agent --config /etc/lunarscope/config.toml
   ```

   Result: `/usr/local/bin/lunarscope-agent` (755), `/etc/lunarscope/config.toml`
   (`root:lunarscope`, 640, with agent id, new `lsk_…` key and master URL),
   the unit in `/etc/systemd/system`, system user `lunarscope`. The same link
   again: 404, `this install link is unknown, already used or expired`.
6. **Agent running** as `lunarscope` (long-running, like systemd would):

   ```text
   lunarscope-agent 0.3.0 started, master http://127.0.0.1:3030
   configuration version 1: scans [ssh_scan, firewall_scan, package_scan, baseline_scan], daily scan at 02:00 UTC
   scan cycle: 7 finding(s) in 1412 ms; accepted 7, rejected 0, not sent 0
   next scan at 02:00 UTC (in 11 h 50 min)
   ```

   Dashboard (filtered on this agent): `shadow_permissions` Pass,
   `curl_absent` Low ("Failed: curl is not installed (curl is installed)"),
   plus the built-in results. The agent reports its real hostname, so with
   the host network it shows as "fedora".
7. **Switch off without reinstalling**: `baseline_scan` switched off on the
   agent's card at 14:10 UTC → the card's counts drop its results right away.
   At its next 5-minute check the running agent picked it up by itself,
   without being reinstalled or restarted:

   ```text
   new configuration from the master (version 2), scanning now
   configuration version 2: scans [ssh_scan, firewall_scan, package_scan], daily scan at 02:00 UTC
   scan cycle: 4 finding(s) in 1127 ms; accepted 4, rejected 0, not sent 0
   next scan at 02:00 UTC (in 11 h 45 min)
   ```

Not tested here: systemd on a real server (the container has no systemd; the
unit is the same file tested in step 20), `--public-url` behind Caddy.

## Not done / known limits

- No "Trigger scan" button and no certificate/domain expiry (see decisions).
- Rule scans can't run commands by design; anything beyond the six test types
  needs a new test type in the agent (= new agent release) or a built-in module.
- A new built-in module needs a migration that adds its row to `scans`.
- Refreshing the install page re-posts the form and creates another agent
  (the browser warns first); delete the extra one on the Agents page.
- The time field shows the browser's clock style (e.g. "02:00 AM"); the value
  is always 24-hour UTC.
- Texts from agents (descriptions, remediations) are not translated.
- ~~Built-in scans that only report problems (e.g. `ssh_config_readable`) still
  stay in the list after the problem is gone.~~ Fixed in the same release:
  [fix-0.3.0-stale-findings.md](fix-0.3.0-stale-findings.md).

## Docs updated

- [Agent code overview](../phase-2-lunarscope-agent/code-overview.md) and
  [master code overview](code-overview.md): 0.3.0.
- [README](../README.md): link to this file.

## Commit and tag (done by hand)

Agent, from `repos/lunarscope-agent` (`agent-code.zip` and your `README.md`
change are not part of this; leave them out or add them yourself):

```bash
git add Cargo.toml Cargo.lock config.toml scripts/measure.sh src
git status
git commit -m "Get scans and scan time from the master, rule scans, daily schedule (v0.3.0)"
git pull --rebase origin main
git tag -a v0.3.0 -m "lunarscope-agent v0.3.0"
git push origin main
git push origin v0.3.0
```

Master, from `repos/lunarscope-master`:

```bash
git add Cargo.toml Cargo.lock lunarscope-master.service install migrations src static templates
git status
git commit -m "New GUI, agent management, rule scans, install links, dashboard login, EN/NL (v0.3.0)"
git pull --rebase origin main
git tag -a v0.3.0 -m "lunarscope-master v0.3.0"
git push origin main
git push origin v0.3.0
```

Docs, from `repos/lunarscope-docs`:

```bash
git add building-phase
git status
git commit -m "Document agent and master v0.3.0, login, daily scans and code overviews"
git push origin main
```
