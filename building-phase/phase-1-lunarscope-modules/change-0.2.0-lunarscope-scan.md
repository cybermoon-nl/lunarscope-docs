# Change (0.2.0) — `lunarscope_scan`: Lunarscope checks itself

**Repos:** `lunarscope-modules` 0.2.0, `lunarscope-master` 0.7.0 (migration
and texts), `lunarscope-agent` 0.5.0 (dependency only)
**Date:** 2026-11-24
**Status:** Done — code and tests; checked live on the dev laptop; mutation
checks; the agent could not be built from git yet (tag `v0.2.0` of the
modules does not exist, no tag or push done); not committed yet

## Why

Lunarscope scans servers for weak settings, but did not look at its own
installation. A loose `config.toml` (it holds the API key) or an agent that
runs as root would be a hole in the tool that is meant to find holes.

## What was built

### 1. Module `lunarscope_scan` (modules 0.2.0)

`src/modules/lunarscope_scan.rs`, `LunarscopeScan`, name `lunarscope_scan`,
registered in `mod.rs`, `lib.rs` and `all_modules`.

It works on a root path (`/` for real; tests use a temporary tree) and
detects what is installed:

- **agent:** `etc/lunarscope/config.toml` exists;
- **master:** `usr/local/bin/lunarscope-master` exists, or a unit
  `lunarscope-master.service` / `lunarscope.service` that contains
  `lunarscope-master`.

Nothing found = one Low finding ("nothing was checked").

| Check | Part | Bad result |
|-------|------|-----------|
| `lunarscope_agent_config_private` | agent | High: config readable by every user |
| `lunarscope_agent_config_owner` | agent | High: not root-owned or writable by others |
| `lunarscope_agent_master_https` | agent | High: results go to the master over plain http (only to this server is fine); Low when unreadable |
| `lunarscope_agent_api_key` | agent | Medium: example or too short key; Low when unreadable |
| `lunarscope_agent_binary` | agent | Critical: binary not root-owned or writable by others |
| `lunarscope_agent_service` | agent | High: unit runs as root; Medium: sandbox settings missing |
| `lunarscope_master_binary` | master | Critical: same rule as the agent binary |
| `lunarscope_master_secrets_private` | master | High: a secret in `/etc/lunarscope` readable by others or writable by the group (mask `0o027`) |
| `lunarscope_master_data_private` | master | High: the data directory, database, WAL or a backup readable by other users |
| `lunarscope_master_listen_local` | master | High: master listens on anything but 127.x / `[::1]` / localhost |
| `lunarscope_master_https_proxy` | master | Medium: no Caddy, or it does not point at the master; Low: TLS 1.3 not set |

A file that cannot be read gives a Low finding with the error ("Permission
denied"), not a failure of the whole scan. 12 tests in the module.

### 2. Master 0.7.0

- Migration `0010_lunarscope_scan.sql`: the scan row `lunarscope_scan`
  (built-in), switched on for **existing agents**, and `config_version + 1`
  so agents fetch their configuration again. New agents get it from the
  trigger that already adds all built-in scans.
- i18n (EN and NL): `scanname_lunarscope_scan` and, for each of the 11
  checks, `check_`, `problem_`, `why_` and `fix_` texts. The text test is
  extended so a missing key fails.
- Several tests updated: there are now **4** built-in scans.
- Master 371 tests pass (370 before the SMTP route test added today).

### 3. Agent 0.5.0

Only `Cargo.toml`: version 0.5.0 and the modules tag `v0.2.0`. An older agent
does not know the module and skips it. Because the tag does not exist yet,
the agent was tested with a **temporary path dependency**: 77 tests pass.
`Cargo.toml` and `Cargo.lock` were left as they are.

## Checked live (dev laptop, user `gijs`)

The module run on the laptop (which has the master, not the agent):

| Check | Result | Why |
|-------|--------|-----|
| master binary | Pass | root-owned, not writable |
| listen_local | Pass | `127.0.0.1:3030` |
| https_proxy | Medium | no Caddy on the laptop |
| secrets_private | Low "Permission denied" | user `gijs` cannot enter `/etc/lunarscope` |
| data_private | Low "Permission denied" | same for `/var/lib/lunarscope` |

The two Low results are right: the real agent runs as user `lunarscope`,
which can enter both directories. The agent checks are in the next document
(agent update test): all 6 Pass after a normal install, and config, binary
and service turn High, Critical and High after loosening them
(`test-2026-11-24-agent-update-and-mfa.md`).

## Design decisions

- **Root path argument.** The module is testable on a fake tree and never
  needs root for its tests.
- **Unreadable is Low, not an error.** The agent runs as an unprivileged
  user; a check that cannot look says so and the scan goes on.
- **Binary check is Critical.** Whoever can replace the binary runs their own
  code as the service, and the agent's update step runs it as root.
- **Plain http to localhost is fine.** The default dev set-up uses it.
- **Master part only when a master is found**, so an agent-only server gets
  no false "no proxy" findings.

## Mutation checks

Each deliberate bug applied, the whole `cargo test` run, the file restored.

| # | Mutation | Caught by |
|---|----------|-----------|
| 1 | `config_private` ignores the mode | `a_loose_agent_installation_is_reported` |
| 2 | binary check ignores the owner (uid) | `a_loose_agent_installation_is_reported`, `a_well_installed_agent_passes_except_ownership_in_tests` |
| 3 | `is_local_host` always true | `a_loose_agent_installation_is_reported`, `plain_http_is_only_fine_to_this_server` |
| 4 | `agent_service` does not treat `User=root` as bad | `a_loose_agent_installation_is_reported`, `the_service_needs_its_own_user_and_the_sandbox` |
| 5 | `secrets_private` mask `0o007` instead of `0o027` | `a_master_is_found_and_checked` |
| 6 | `listen_local` accepts `0.0.0.0` | `where_the_master_listens`, `a_master_is_found_and_checked` |
| 7 | `https_proxy` skips the TLS 1.3 check | `the_proxy_must_point_at_the_master_with_tls_1_3` |
| 8 | `scan()` runs the master part for an agent-only install | `a_well_installed_agent_passes_except_ownership_in_tests`, `nothing_installed_gives_one_low_finding` |
| 13 | migration 0010 does not enable the scan for existing agents | `db::tests::migration_3_keeps_existing_agents_and_results_as_they_were` |

All 9 caught; none survived.

## Tests

Modules **59** unit tests + **7** public API tests, all passing. Master
**371**. Agent 77 (with the temporary path dependency).
