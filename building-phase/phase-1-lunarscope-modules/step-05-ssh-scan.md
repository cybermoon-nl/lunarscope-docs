# Step 5 — First module: `ssh_scan`

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done

## Goal

Create `src/modules/ssh_scan.rs`: read `/etc/ssh/sshd_config`, check
`PermitRootLogin` and `PasswordAuthentication`, and return a `Finding` per
check.

## What was done

### Files

| File | Change |
|------|--------|
| `src/modules/ssh_scan.rs` | New — the `SshScan` module |
| `src/modules/mod.rs` | New — only `pub mod ssh_scan;` for now |
| `src/lib.rs` | Added `pub mod modules;` |

`mod.rs` and the `pub mod modules;` line are needed now so the module is
compiled and checked at all. Step 8 completes `mod.rs` with the other modules
and the public re-exports.

### Structure of the module

```rust
pub struct SshScan;

impl ScanModule for SshScan {
    fn name(&self) -> &str { "ssh_scan" }
    fn description(&self) -> &str { "Checks PermitRootLogin and PasswordAuthentication in sshd_config" }
    fn run(&self) -> Vec<Finding> { scan_config(Path::new("/etc/ssh/sshd_config")) }
}
```

Internally:

| Function | Responsibility |
|----------|----------------|
| `scan_config(path)` | Reads the config, runs both checks; returns one `ssh_config_readable` finding if the file can't be read |
| `collect_directives(path, out)` | Parses the file into `(keyword, value)` pairs in sshd's reading order, following `Include` and stopping at `Match` |
| `expand_include(base, pattern)` | Resolves an `Include` path, including a `*` wildcard in the file name |
| `lookup(directives, keyword)` | Returns the **first** value for a keyword |
| `check_permit_root_login(value)` | Builds the `ssh_permit_root_login` finding |
| `check_password_authentication(value)` | Builds the `ssh_password_authentication` finding |

`run()` only passes the real path to `scan_config()`. Because of that split,
the parsing and checks can be tested in step 9 against temporary config files
instead of the real system file.

### Findings produced

| `check_name` | Condition | Severity |
|--------------|-----------|----------|
| `ssh_permit_root_login` | `no` | Pass |
| | `prohibit-password`, `without-password`, `forced-commands-only`, or not set | Pass |
| | anything else (`yes`) | **High** |
| `ssh_password_authentication` | `no` | Pass |
| | `yes` or not set | **Medium** |
| `ssh_config_readable` | config file can't be read (instead of the two above) | **Low** |

Every failing finding includes a `remediation` with the exact line to set.

## Choices and justification

### Parsing follows how sshd itself reads the config

The SQ6 proof of concept read the file into a `HashMap`, which keeps the
**last** value of a keyword and ignores `Include`. That gives wrong results
on a standard Ubuntu 24.04 server. The module therefore follows the
`sshd_config(5)` rules:

- **First value wins.** For most keywords sshd uses the first value it
  reads, so `lookup()` returns the first match.
- **`Include` is followed.** Ubuntu 24.04's `sshd_config` starts with
  `Include /etc/ssh/sshd_config.d/*.conf`, and cloud images set
  `PasswordAuthentication` in `50-cloud-init.conf`. Because the include is
  at the top, a value there takes precedence over the same keyword later in
  the main file. Without following the include the scanner would report
  "disabled" while password login is actually enabled. Matching files are
  processed in lexical order, as sshd does; relative paths resolve against
  the config's directory (`/etc/ssh`).
- **Parsing stops at `Match`.** Directives after a `Match` line only apply
  to some users/hosts. They don't change the global setting, so they are
  not counted.
- **Keywords are case-insensitive, and `Keyword=value` is accepted** — both
  are valid sshd syntax.

### Defaults when a keyword is not set

- `PermitRootLogin` defaults to `prohibit-password` since OpenSSH 7.0
  (Ubuntu 24.04 ships 9.6). Root can then only log in with a key, which is
  treated as Pass. The PoC assumed the old default `yes`, which would give
  a false High on every default install.
- `PasswordAuthentication` defaults to `yes`, so a missing line is a
  Medium finding.

### Severities

- **High for root password login** — a directly reachable, high-value
  brute-force target. Not Critical because exploitation still needs the root
  password.
- **Medium for password authentication** — allows brute-force/credential
  stuffing against every account, but is common and often intentional on SMB
  servers.
- **Low for an unreadable config** — not a vulnerability by itself, but the
  dashboard must show that the check could not be done. Per step 4, a module
  reports this as a finding instead of returning an error.

### Pass findings are always returned

Every check returns exactly one finding, including on success. This way the
master can tell "checked and OK" apart from "not checked", and a later
successful scan visibly replaces an earlier failing one per `check_name`.

### Limitations (known, accepted for the prototype)

- Only a `*` wildcard in the **file name** of an `Include` is supported (no
  `?`, `[...]` or wildcards in directories). That covers the Ubuntu default
  and keeps the module free of extra dependencies.
- An unreadable *included* file is skipped silently; only an unreadable main
  file produces a finding.
- The module reads the config on disk. If sshd was not restarted after a
  change, the running daemon may still use old values. `sshd -T` would show
  the effective config but needs root, while the agent runs as the
  unprivileged `lunarscope` user (step 20).

## Verification

```text
$ cargo build                 → Finished, no warnings
$ cargo clippy -- -D warnings → Finished, no warnings
$ cargo fmt --check           → no changes
```

`scan_config()` was run against four sample configs with a temporary test
(removed afterwards). These cases are now permanent unit tests, written in step 6 — see [testing.md](testing.md):

| Case | Config | Result |
|------|--------|--------|
| a | Ubuntu-like: `Include .../sshd_config.d/*.conf`, drop-in `50-cloud-init.conf` with `PasswordAuthentication yes`, main file `PermitRootLogin yes` + `PasswordAuthentication no`, a `Match` block, and a non-`.conf` file in the directory | root login **High**, password auth **Medium** (drop-in wins over main file; non-`.conf` file ignored) |
| b | Empty file | root login **Pass** (default `prohibit-password`), password auth **Medium** (default `yes`) |
| c | `permitrootlogin=no`, `PASSWORDAUTHENTICATION   No` | both **Pass** |
| missing | Path does not exist | one `ssh_config_readable` **Low** |

Running `SshScan.run()` on the development machine (Fedora, where
`sshd_config` is root-only `0600`) returned the
`ssh_config_readable` Low finding with "Permission denied". This is the
expected behaviour. On Ubuntu 24.04 the file is `0644`, so the unprivileged
agent can read it.

## Next step

Step 6 — second module: `firewall_scan`.
