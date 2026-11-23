# lunarscope-agent — code overview

**Repo:** `lunarscope-agent`
**Version described:** 0.4.0 (signed self-update, see section 12 and
[change-0.4.0-agent-self-update.md](../phase-3-lunarscope-master/change-0.4.0-agent-self-update.md);
scans and scan time from the master, rule scans: see
[change-0.3.0-agent-management.md](../phase-3-lunarscope-master/change-0.3.0-agent-management.md))
**Date:** 2026-11-09, updated 2026-11-16

A walk through the agent's code: what each file does, how the parts fit
together, and where to look when you want to change something. The step
files (11–21), [fix-0.1.1-ca-certificates.md](fix-0.1.1-ca-certificates.md)
[change-0.2.0-daily-scan-time.md](change-0.2.0-daily-scan-time.md) and
[change-0.3.0-agent-management.md](../phase-3-lunarscope-master/change-0.3.0-agent-management.md)
explain *why* things were built this way; this file explains *what is
there*.

## 1. What the agent does

The agent is a small Rust program that runs on every monitored Ubuntu
server. It:

1. reads `/etc/lunarscope/config.toml` (who it is, where the master is),
2. asks the master which scans to run and when (`GET /api/agent-config`):
   built-in modules from `lunarscope-modules` and **rule scans** (checks
   defined as data on the master),
3. runs them once at startup, then every day at `scan_time` (UTC), and
   right away when the master's configuration changes (it checks every
   5 minutes),
4. sends every finding as its own `POST /api/scan-result` to the master
   over HTTPS (TLS 1.3 only), authenticated with a Bearer API key.

It does not listen on any port, store anything on disk or run anything as
root. It runs as the system user `lunarscope` under systemd.

## 2. Files

| File | Lines | What it is |
|------|------:|------------|
| `Cargo.toml` | 19 | Crate metadata, dependencies, release profile |
| `Cargo.lock` | — | Exact dependency versions (always build with `--locked`) |
| `config.toml` | 17 | Example config, placeholders only (the install script writes the real one) |
| `src/main.rs` | ~430 | Entry point: arguments, daily schedule, polling the master, scan loop |
| `src/config.rs` | ~320 | Loading and validating the config, `ScanTime` |
| `src/remote.rs` | ~135 | The configuration from the master and which modules it turns into |
| `src/rules.rs` | ~490 | Rule engine: the six test types of rule scans |
| `src/sender.rs` | ~610 | Fetching the configuration, building the JSON and sending it to the master |
| `lunarscope-agent.service` | 48 | systemd unit with hardening |
| `scripts/measure.sh` | 50 | Measures binary size, cycle time and memory |

About half of each `.rs` file is unit tests (`#[cfg(test)] mod tests` at
the bottom).

### Dependencies (`Cargo.toml`)

| Crate | Used for |
|-------|----------|
| `lunarscope-modules` (git, tag `v0.1.0`) | `Finding`, `Severity`, `ScanModule`, `all_modules()` |
| `reqwest` 0.13, only feature `rustls` | HTTPS client. No OpenSSL; trusted CAs come from the system via `rustls-platform-verifier` |
| `serde`, `serde_json` | Config deserialisation, the master's JSON configuration and the JSON body |
| `tokio` (`rt`, `macros`, `time`) | Single-threaded async runtime and `sleep` for the schedule |
| `toml` | Parsing `config.toml` |

The release profile (`opt-level = "s"`, `lto`, `codegen-units = 1`,
`strip`) makes the binary small (about 3.2 MB, step 19).

## 3. Flow through the program

```text
main()                                   src/main.rs
 └─ run()
     ├─ parse_args()                     --config <path>, --once
     ├─ Config::load()                   src/config.rs  (read → parse → validate)
     ├─ Reporter::new()                  src/sender.rs  (endpoints + HTTP client)
     ├─ print "started" line
     ├─ fetch_config()                   GET /api/agent-config (retry every 60 s)
     ├─ modules_for(config)              src/remote.rs  (built-in + rule scans)
     └─ --once ? cycle() once
               : cycle() at startup, then loop {
                     wait_for_scan(next)  poll config every 5 min while waiting
                       new version → cycle() now with the new config
                       next reached → cycle()
                 }

cycle()
 ├─ scan()                               run every module, catch panics
 ├─ Reporter::send_all()                 one POST per finding
 └─ print "scan cycle: …" summary line
```

Everything is printed to stderr with `eprintln!`. Under systemd that ends
up in the journal (`journalctl -u lunarscope-agent`).

### Exit codes

| Code | When |
|-----:|------|
| 0 | `--once` and every finding was accepted |
| 1 | Startup error: bad arguments, config, HTTP client could not be built, or (`--once`) the master's configuration could not be fetched. Printed as `lunarscope-agent: <message>` |
| 2 | `--once` and at least one finding was rejected or not sent |

Without `--once` the loop never ends on its own; the agent only stops when
systemd stops it.

## 4. `src/main.rs`

### `Args` and `parse_args`

Hand-written argument parsing (no `clap`, to keep the binary small).

- `--config <path>`: default `/etc/lunarscope/config.toml` (`DEFAULT_CONFIG`).
- `--once`: run one cycle and exit; meant for testing an installation.
- `-h` / `--help`: returns the usage text as an error, so it is printed and
  the program exits with code 1.
- Anything else is an error ("unknown argument").

`parse_args` takes an iterator instead of reading `std::env::args()`
itself, so the tests can pass their own arguments.

Which modules run is no longer decided here but by the master; see
`remote.rs` (section 6).

### `scan`

Runs every module's `run()` and collects all findings as `ScanResult`
(finding + `scan_type`, which is the module name).

`scan()` also returns the names of the modules that finished (didn't
panic), for the scan-complete message. Each `run()` is wrapped in
`panic::catch_unwind`. If a module panics, the
agent does not crash. Instead it adds a finding `<module>_crashed` with
severity `Low`, so the problem shows up on the dashboard, and the other
modules still run.

### `cycle`

One scan cycle: `scan()`, then `send_all()`, then one log line:

```text
scan cycle: 7 finding(s) in 12 ms; accepted 7, rejected 0, not sent 0
```

Then, only when sending wasn't aborted, `report_complete()` tells the master
which checks each finished module reported (`POST /api/scan-complete`), so
the master drops checks that are gone; the agent logs `master removed N
check(s) that are no longer reported` when it did. Not after an aborted
cycle, because the master would drop checks that just weren't sent.

Returns `true` if everything was accepted (`SendSummary::all_accepted`).
That value is only used for the exit code of `--once`.

### `next_scan`, `sleep_until`, `format_wait` (the schedule)

- `next_scan(now, scan_time)` returns the Unix time of the first
  `scan_time` **strictly after** `now`: today if it is still to come,
  otherwise tomorrow. Because of "strictly", a cycle that finishes in the
  same second as the scan time doesn't make it run again.
- `sleep_until(target)` sleeps in steps of at most `MAX_SLEEP` (10 minutes)
  and reads the wall clock again after each step. tokio's `sleep` uses a
  monotonic clock, which doesn't see a clock correction or a suspended VM;
  with the steps the scan is off by at most 10 minutes in those cases.
- `format_wait(seconds)` gives `"11 h 05 min"` for the log line.

All times are Unix seconds from `unix_timestamp()` in `sender.rs`, so the
schedule is in UTC.

### `hostname`

Reads `/proc/sys/kernel/hostname`; falls back to `"unknown"`. No extra
crate needed.

### `run` and `main`

`run()` does the setup shown in section 3 and returns
`Result<bool, String>`. All error types are turned into text with
`to_string()` here, so `main()` only has to print them.

- `fetch_config_until_ok()` asks the master for its configuration and tries
  again every 60 s (`RETRY_SECONDS`) until it answers: without it the agent
  doesn't know what to scan. `--once` tries only once.
- `log_config()` prints `configuration version 3: scans [ssh_scan, …],
  daily scan at 02:00 UTC`.

Without `--once`:

1. One cycle right at startup, so a new install or restart shows results at
   once.
2. Then a loop: print `next scan at 02:00 UTC (in 14 h 06 min)` and call
   `wait_for_scan(next)`. That sleeps in steps of at most 5 minutes
   (`CONFIG_POLL_SECONDS`) and asks the master for its configuration after
   each step:
   - a **different `version`** → log `new configuration from the master
     (version 4), scanning now`, scan right away with it, then wait for
     the next `scan_time` again;
   - the same version, or the master can't be reached → keep the current
     configuration and keep waiting;
   - `next` reached → scan, and compute the next scan with
     `next_scan(unix_timestamp().max(next), …)`. The `.max(next)` makes sure
     the agent moves on to the next day even if the clock was set back.

`#[tokio::main(flavor = "current_thread")]`: one thread is enough, the
agent does one thing at a time. This saves memory.

## 5. `src/config.rs`

### `Config`

```toml
agent_id = "<uuid from the master>"
api_key = "<key from the master>"
master_url = "https://lunarscope.cybermoon.nl"
```

The install script from the master's "Add agent" page writes this file.
Which scans run and when is set on the master.

`#[serde(deny_unknown_fields)]` makes a misspelled key an error instead of
being ignored. That includes the keys of older versions (`interval_seconds`,
`scan_time`, `[modules]`), so an old config must be cleaned up before 0.3.0
starts; the error names the key.

### `ScanTime`

The type of the master's `scan_time` (UTC: 02:00 UTC is 03:00 in the
Netherlands in winter and 04:00 in summer): hour and minute. It is read from
the string with `#[serde(try_from = "String")]`, which calls
`TryFrom<String>`:

- Accepted: exactly `HH:MM`, two digits on both sides, hour 00–23,
  minute 00–59.
- Anything else (`"2:00"`, `"24:00"`, `"+1:00"`, `"02:00:00"`, a number, …)
  is refused: `scan_time '2:00' is not a time like "02:00" (HH:MM, 24-hour
  clock, UTC)`, so a broken configuration from the master isn't used.
- `seconds_of_day()`: seconds after midnight, used by `next_scan`.
- `Display`: `"02:00 UTC"`, used in the log lines.

### `ConfigError`

| Variant | Message starts with | When |
|---------|---------------------|------|
| `Read` | `could not read config:` | File missing or not readable |
| `Parse` | `invalid config file:` | Not valid TOML, missing field, wrong type, unknown field |
| `Invalid` | `invalid config value:` | Valid TOML, but a value breaks a rule (below) |

### `Config::load` → `parse` → `validate`

- `load(path)` reads the file and prints a **warning** if it is readable by
  every user (`mode & 0o004`), because it contains the API key. It does not
  refuse to start.
- `parse(content)` is separate from `load` so tests can work without
  files.
- `validate()` checks:
  - `agent_id` and `api_key` are not empty or only spaces,
  - `master_url` passes `master_base_url()`.

### `master_base_url`

Parses `master_url` and only accepts:

- `https://…`, or
- `http://` to `localhost`, `127.0.0.1` or `[::1]` (local development).

Plain http to any other host is refused, because the API key would travel
unencrypted. Other schemes (`ftp://`) are refused too.

## 6. `src/remote.rs` and `src/rules.rs`

### `RemoteConfig` (what the master sends)

```json
{
  "version": 4,
  "scan_time": "02:00",
  "modules": ["ssh_scan", "firewall_scan", "baseline_scan"],
  "rule_scans": [{"name": "baseline_scan", "description": "…", "checks": [ … ]}]
}
```

`modules_for(config)` turns it into the list of modules to run, in the
master's order: a built-in module from `all_modules()` by name, otherwise a
rule scan from `rule_scans` by name. A name the agent doesn't know (for
example a module only a newer agent has, or a rule scan whose definition is
missing) is skipped with a warning; a name listed twice runs once.

### Rule scans

A rule scan is a list of checks. Each check has a `check_name`, a
`severity` (`Critical`/`High`/`Medium`/`Low`, used when it fails), a
`description` of what is required, an optional `remediation` and a `test`:

| Test type | Fields | Passes when |
|-----------|--------|-------------|
| `file_exists` | `path`, `expect` | the file exists (`expect = false`: doesn't) |
| `file_contains` | `path`, `text`, `expect` | the text is in the file |
| `config_value` | `path`, `key`, `value` | the first `key value` / `key=value` line (no comments, case ignored) has that value |
| `file_mode_max` | `path`, `mode` | the permission bits don't go beyond `mode` (octal, e.g. `640`) |
| `service_active` | `service`, `expect` | `systemctl is-active` says `active` |
| `package_installed` | `package`, `expect` | `dpkg-query` says installed (`ii`) |

`RuleScan` implements the same `ScanModule` trait as the built-in modules,
so `scan()` runs it the same way (including `catch_unwind`). Results:

| Outcome | Finding |
|---------|---------|
| passed | `Pass`, `OK: <description>` |
| failed | the check's severity, `Failed: <description> (<what was found>)` |
| couldn't test | `Low`, `Could not check: <description> (<error>)` |

Safety: there is no test type that runs a command chosen by the master.
Paths must be absolute without `..`; service and package names may only
use `A-Z a-z 0-9 @ . _ + : -` and not start with `-`, because they go to
`systemctl`/`dpkg-query` as one argument; files are read up to 1 MiB.
The agent's systemd hardening still applies (read-only, no home
directories).

## 7. `src/sender.rs`

### Types

| Type | Purpose |
|------|---------|
| `ScanResult` | A `Finding` plus `scan_type` (module name) |
| `Payload` | The JSON body (private) |
| `SendSummary` | Counts for one cycle: `accepted`, `rejected`, `skipped`, and `aborted` (reason) |
| `ReporterError` | Why `Reporter::new` failed: `Config(ConfigError)` or `HttpClient(String)` |
| `Reporter` | HTTP client + endpoints + credentials, created once at startup |

### The JSON body

`Payload` follows the architecture document (5.2). The finding's fields
are flattened into the top level with `#[serde(flatten)]`:

```json
{
  "agent_id": "550e8400-…",
  "hostname": "web-01",
  "scan_type": "ssh_scan",
  "check_name": "ssh_permit_root_login",
  "severity": "High",
  "description": "Root can log in",
  "remediation": "Set PermitRootLogin no",
  "timestamp": 1791072132
}
```

- `remediation` is `null` when there is nothing to fix.
- `timestamp` is Unix **seconds** (`unix_timestamp()`), taken right before
  each request. The master rejects timestamps more than 60 seconds off.

If you change this format, the master's `src/routes/api.rs` has to change
with it.

### `Reporter::new`

- Builds the endpoint: base URL + `/api/scan-result`. `Url::join` with a
  leading `/` drops any path in `master_url`, so
  `https://host/some/path` still posts to `https://host/api/scan-result`.
- Builds the reqwest client:
  - `User-Agent: lunarscope-agent/<version>`,
  - minimum TLS version 1.3,
  - 10 s request timeout, 5 s connect timeout.
- If building the client fails, it returns `ReporterError::HttpClient` with
  the full error chain and the hint "(is the ca-certificates package
  installed?)". That is the usual cause: without system CA certificates,
  the client can't be built (fix 0.1.1).

### `fetch_config`

`GET /api/agent-config` with `Authorization: Bearer <api_key>`. Clear errors
for a 401 ("master rejected the API key"), another status, invalid JSON
("invalid configuration from master") and network problems (with
`error_chain`). Larger than 1 MiB is refused.

### `completed_scans` and `report_complete`

`completed_scans(results, completed)` groups the check names per finished
module (a finished module without findings gets an empty list).
`report_complete()` posts them to `/api/scan-complete` and returns how many
results the master removed; a 404 means an older master and is logged as
such. See
[fix-0.3.0-stale-findings.md](../phase-3-lunarscope-master/fix-0.3.0-stale-findings.md).

### `send_all`

Sends every finding as its own request, one after the other:

| Answer from the master | What happens |
|------------------------|--------------|
| 2xx | `accepted += 1` |
| 401 Unauthorized | Log "check api_key and agent_id", **stop the cycle**: the rest would be rejected too. Remaining findings count as `skipped` |
| Other status (400, 500, …) | Log it, `rejected += 1`, **continue** with the next finding |
| Network/TLS error | Log "could not reach master …" with the error chain, **stop the cycle**, all remaining findings are `skipped` |

Nothing is retried or saved. The next cycle sends a fresh scan anyway.

### `send`

One request: `Authorization: Bearer <api_key>`,
`Content-Type: application/json`, body from `payload_json()`. Returns the
status code; only network errors are `Err`.

### `error_chain`

Joins an error with all its `source()` causes, separated by `: `, and skips
a cause whose text is already in the message. reqwest's top-level message
("error sending request") hides the useful part ("Connection refused", a
certificate problem), so this is used for both request errors and client
build errors.

## 8. Tests

`cargo test --locked` runs 63 unit tests.

| File | Tests | Highlights |
|------|------:|------------|
| `config.rs` | 14 | Valid config, the repo's own `config.toml` is valid, each kind of parse/validation error, old keys (`interval_seconds`, `scan_time`, `[modules]`) refused, good and bad `ScanTime` values (also from JSON), http-only-for-localhost, reading from disk |
| `main.rs` | 14 | A real `cycle()` against a fake master ends with scan-complete, and sends none after an aborted cycle; argument parsing, panicking module becomes a finding (and isn't listed as finished), real modules all produce results, `next_scan` (today/tomorrow, exactly at the time, around midnight, never more than a day away), `sleep_until`, `format_wait`, hostname never empty |
| `remote.rs` | 7 | The master's JSON, order of built-in and rule scans, unknown/duplicate names, definitions that aren't enabled don't run |
| `rules.rs` | 11 | Reading rule scans, `Pass` not allowed as fail severity, no `command` type, every test type with `expect` both ways, sshd_config rules, unreadable file → Low, paths and names checked |
| `sender.rs` | 17 | `completed_scans`, scan-complete request and its errors; Exact JSON format, timestamp in seconds, endpoint building, real HTTP requests to a **fake master**, 401 stops the cycle, other errors don't, unreachable master, `error_chain`, the `ReporterError` messages, `fetch_config` (sends the key, explains every error) |

`fake_master()` in `sender.rs` is a tiny HTTP server on `127.0.0.1` with a
random port. It answers each request with the next status code from a list
and passes what it received back to the test over a channel. That lets the
tests check headers and body of real requests without a real master.

Note: the six fake-master tests need a working HTTP client, so they fail on
a system without `ca-certificates` (see the re-test of 2026-11-04).

Other checks used for releases:

```bash
cargo clippy --all-targets --all-features --locked -- -D warnings
cargo fmt --check
```

## 9. `lunarscope-agent.service`

- Runs `/usr/local/bin/lunarscope-agent --config /etc/lunarscope/config.toml`
  as user and group `lunarscope`.
- Starts after the network is online.
- `Restart=on-failure` after 10 s, but at most 5 starts in 5 minutes, so a
  broken config doesn't restart forever.
- Hardening: no capabilities, read-only file system (`ProtectSystem=strict`),
  no home directories, private `/tmp` and devices, system call filter,
  `MemoryDenyWriteExecute`, only `AF_UNIX` (for `systemctl` over D-Bus) and
  `AF_INET`/`AF_INET6` (for the master). `systemd-analyze security` rates it
  1.2 OK (step 20).

Requirement on the server: the `ca-certificates` package (step 20). The
master's install script installs it if it's missing, and writes this unit.

## 10. `scripts/measure.sh`

`scripts/measure.sh <config.toml> [binary] [runs]` prints:

- binary size,
- average `--once` time over N runs,
- peak memory of one `--once` run (`/usr/bin/time`), including child
  processes like `apt-get`,
- memory and thread count of the long-running agent after 15 s (`/proc`),
  while it waits after its startup scan,
- peak heap with valgrind massif, if it is installed.

The config should point at a reachable test master. Results are in step 19.

## 11. Where to change things

| You want to… | Change |
|--------------|--------|
| Add a config option | Field in `Config` (`config.rs`), a rule in `validate()` if needed, `config.toml`, and the `VALID` test config |
| Add a command-line flag | `Args`, `parse_args`, `USAGE` in `main.rs` |
| Add a check without a new agent | A rule scan on the master (Scans → New rule scan) |
| Add a built-in scan module | In `lunarscope-modules` (new tag), then update the tag in `Cargo.toml`; the agent picks it up through `all_modules()`. The master needs a migration adding its row to `scans` |
| Add a rule test type | `Test` + `evaluate` in `rules.rs` **and** `Test` + `validate_test` in the master's `src/rule_scans.rs` (new agent release) |
| Change how often the agent checks for a new configuration | `CONFIG_POLL_SECONDS` in `main.rs` (and the "within 5 minutes" text on the master) |
| Change the JSON sent | `Payload` and `payload_json` in `sender.rs` **and** the master's API |
| Change how errors from the master are handled | The `match` in `send_all` |
| Change timeouts or TLS settings | Constants at the top of `sender.rs` and `Reporter::new` |
| Change the schedule (e.g. local time, more than once a day) | `ScanTime` in `config.rs`, `next_scan` and `run()` in `main.rs`, the scan time field and check on the master, and `STALE_AFTER_SECONDS` in the master's `src/routes/dashboard.rs` |

After any change: run the tests, clippy and fmt, bump the version in
`Cargo.toml`, and add a fix/change file in this folder.

## 12. New in 0.4.0

Sections 1–11 describe 0.3.0; this is what 0.4.0 adds. The why is in
[change-0.4.0-agent-self-update.md](../phase-3-lunarscope-master/change-0.4.0-agent-self-update.md)
and [change-0.4.0-time-zone-settings.md](../phase-3-lunarscope-master/change-0.4.0-time-zone-settings.md).

### Commands (`main.rs`: `Command`, `parse_command`)

| Command | What it does |
|---------|--------------|
| `lunarscope-agent [--config <path>] [--once]` | As before (`Command::Run`) |
| `lunarscope-agent --version` | Prints `lunarscope-agent 0.4.0` |
| `lunarscope-agent apply-update [--state-dir <dir>] [--target <path>]` | As root before the agent starts (`ExecStartPre=+`): installs a staged update after checking it again. Always exits 0 |
| `lunarscope-agent update-keygen <dir>` | Makes `update-signing.key` (600) and `update-key.pub` in `<dir>` |
| `lunarscope-agent update-sign --key <file> [--version x.y.z] <binary>` | Writes `<binary>.sig`; the version defaults to the agent's own |

### `src/update.rs`

| Item | What it does |
|------|--------------|
| `UpdateOffer` | `{version, sha256, signature}`: in `<binary>.sig` and in the master's configuration (`RemoteConfig.update`) |
| `message()` | The signed text: `lunarscope-agent update\nversion=…\nsha256=…\n` |
| `built_in_key()` | The public key from `update-key.pub` (`include_str!`); `None` = updates off |
| `parse_version`, `is_newer` | `major.minor.patch` as numbers; only newer versions are installed |
| `check()` | Newer, signature (`verify_strict`), at most `MAX_BINARY_BYTES` (64 MiB), SHA-256 |
| `stage()` | Writes `update/lunarscope-agent` and `update/offer.json` in the state folder |
| `apply()` | Reads the staged binary once, `check()`s it, writes `<target>.new` (755, `fsync`), renames it over the target; removes the staged files in every case |
| `keygen()`, `sign()` | For the developer's laptop |

### Changes in `main.rs`, `sender.rs`, `remote.rs`

- `Wake::Update`: the offer in a fetched configuration differs from the
  current one (and isn't empty). Handled without a scan: `try_update`.
- `try_update(reporter, offer, key)`: skips offers that aren't newer or
  when there's no key; downloads, checks, stages. `true` → `run` returns
  `Outcome::Updated` → exit code `UPDATE_EXIT_CODE` (75), systemd starts the
  agent again and `apply-update` installs it. The key is a parameter so
  tests can use a test key.
- `run` takes the parsed `Args`; it returns `Outcome::Once(bool)` or
  `Outcome::Updated`.
- `Reporter::download_agent()`: `GET /downloads/lunarscope-agent`, 300 s
  timeout, at most 64 MiB.
- `state_dir()`: `$STATE_DIRECTORY` (set by systemd's `StateDirectory=`),
  else `/var/lib/lunarscope-agent`.
- `Wake::NewScanTime` (0.4.0 master time zone): the configuration version is
  the same but `scan_time` (UTC) changed, e.g. at the switch to summer or
  winter time. The agent waits for the new time without scanning now.

### Exit codes (addition to section 3)

| Code | When |
|------|------|
| 75 | An update was staged; systemd restarts the agent (`Restart=on-failure`) |

### Unit file (addition to section 9)

```ini
StateDirectory=lunarscope-agent
StateDirectoryMode=0700
ExecStartPre=+/usr/local/bin/lunarscope-agent apply-update
```

### Where to change things (additions)

| You want to… | Change |
|--------------|--------|
| Use your own update key | `update-keygen`, copy the `.pub` into `update-key.pub`, rebuild, reinstall agents once |
| Change what is signed | `message()` in `update.rs` — old signatures stop working, sign again |
| Change the largest accepted binary | `MAX_BINARY_BYTES` in `update.rs` |

