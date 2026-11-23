# Change 0.2.0 — daily scan at a fixed time instead of an interval

**Repos:** `lunarscope-agent` (0.1.1 → **0.2.0**), `lunarscope-master` (0.1.0 → **0.1.1**, released as **0.2.0**)
**Date:** 2026-11-09
**Status:** Done — code and checks ready; commit + tag by hand

> **Update 2026-11-16:** The master change below was never released as
> 0.1.1. It goes out together with the dashboard login as **master 0.2.0**,
> see [change-0.2.0-dashboard-login.md](../phase-3-lunarscope-master/change-0.2.0-dashboard-login.md). The master commands at the end of this file were replaced by the
> ones in that file. Everything about the agent is unchanged.

## Why

Until v0.1.1 the agent scanned every `interval_seconds` (default 3600, so
every hour). The wish is a scan **once a day at a fixed time**, e.g. at
02:00 at night, when the servers are quiet.

## Decisions

| Question | Choice | Reason |
|----------|--------|--------|
| Where the time is set | In `config.toml` (`scan_time = "02:00"`); the agent stays a long-running service and waits itself | Keeps all agent settings in one file. Rejected: a systemd timer with `OnCalendar=` and `--once` (time would live in systemd, not the config) |
| Clock | **UTC** | No extra crate needed (no time zone database). Downside: 02:00 UTC is 03:00 in the Netherlands in winter (CET) and 04:00 in summer (CEST) |
| Scan at startup | **Yes**, then daily at `scan_time` | A new install or a restart shows results on the dashboard right away |
| Old key `interval_seconds` | **Refused** (`deny_unknown_fields`) | A v0.1.x config must be updated on purpose, instead of silently running on a default. That makes this a breaking config change, so the version is 0.2.0 |

## Agent changes

### `src/config.rs`

- `interval_seconds: u64` and `MIN_INTERVAL_SECONDS` removed.
- New field `scan_time: ScanTime`. `ScanTime` (hour + minute) is read from a
  string with `#[serde(try_from = "String")]`:
  - accepted: exactly `HH:MM`, two digits each, hour 00–23, minute 00–59;
  - refused: `"2:00"`, `"0200"`, `"24:00"`, `"02:60"`, `"+1:00"`,
    `"02:00:00"`, `"02:00 "`, `""`, a number instead of a string.
  - Refused values are a `Parse` error, so the message shows the line:

    ```text
    lunarscope-agent: invalid config file: TOML parse error at line 4, column 13
      |
    4 | scan_time = "2:00"
      |             ^^^^^^
    scan_time '2:00' is not a time like "02:00" (HH:MM, 24-hour clock, UTC)
    ```

- `ScanTime::seconds_of_day()` (seconds after midnight UTC) and `Display`
  (`"02:00 UTC"`).

The minimum-interval check is no longer needed: the shortest time between
two scans is now the startup scan followed by `scan_time`, and after that
always 24 hours.

### `src/main.rs`

The `tokio::time::interval` loop was replaced:

```rust
cycle(&modules, &reporter).await;                       // startup scan
let mut next = next_scan(unix_timestamp(), config.scan_time);
loop {
    eprintln!("next scan at {} (in {})", …);
    sleep_until(next).await;
    cycle(&modules, &reporter).await;
    next = next_scan(unix_timestamp().max(next), config.scan_time);
}
```

| Function | What it does |
|----------|--------------|
| `next_scan(now, scan_time)` | Unix time of the first `scan_time` **strictly after** `now`: today if it is still to come, otherwise tomorrow. "Strictly" means a cycle that finishes in the same second is not run twice |
| `sleep_until(target)` | Sleeps in steps of at most `MAX_SLEEP` (10 min) and checks the wall clock after each step. A clock correction (NTP) or a suspended VM therefore moves the scan by at most 10 minutes. (One `sleep` of 24 h would follow tokio's monotonic clock, which doesn't see those changes) |
| `format_wait(seconds)` | `"11 h 05 min"` for the log line |

`.max(next)`: if the clock was set back during a cycle, the agent still
moves on to the next day instead of picking the same scan time again.

`--once` is unchanged: one cycle, then exit.

Log lines (journal):

```text
lunarscope-agent 0.2.0 started: modules [ssh_scan, firewall_scan, package_scan], daily scan at 02:00 UTC, master https://lunarscope.cybermoon.nl
scan cycle: 7 finding(s) in 12 ms; accepted 7, rejected 0, not sent 0
next scan at 02:00 UTC (in 14 h 06 min)
```

### Other agent files

- `src/sender.rs`: `unix_timestamp()` is now `pub` (used by the schedule).
  Test config uses `scan_time`.
- `config.toml`: `scan_time = "02:00"` with a comment about UTC vs Dutch
  time.
- `scripts/measure.sh`: comment updated. The long-running measurement now
  reads `/proc` while the agent waits after its startup scan.
- `Cargo.toml` / `Cargo.lock`: version 0.2.0.

## Master change

`src/routes/dashboard.rs`: an agent is marked **stale** (last-seen time in
red, on the dashboard and the server page) when it hasn't reported for
`STALE_AFTER_SECONDS`.

| | Before | Now |
|-|--------|-----|
| `STALE_AFTER_SECONDS` | `2 * 3600` (two missed hourly cycles) | `25 * 3600` |

With daily scans, 2 h would have shown every agent as stale for about 22
hours a day. 25 h is one missed daily scan plus one hour of margin for a
slow scan or a small clock difference. Planned as version 0.1.1, released
in master 0.2.0.

No API, database or template change was needed: the master doesn't know or
care how often an agent reports.

## Upgrading an installed agent

In `/etc/lunarscope/config.toml`, replace

```toml
interval_seconds = 3600
```

with

```toml
scan_time = "02:00"
```

then install the new binary and `sudo systemctl restart lunarscope-agent`.
Without this edit the v0.2.0 agent refuses to start:

```text
lunarscope-agent: invalid config file: TOML parse error at line 4, column 1
  |
4 | interval_seconds = 3600
  | ^^^^^^^^^^^^^^^^
unknown field `interval_seconds`, expected one of `agent_id`, `api_key`, `master_url`, `scan_time`, `modules`
```

Update the master too (0.2.0, which includes this change); otherwise every
daily agent shows as stale.

## Tests

### Agent — 42 tests (was 35)

Removed: `negative_interval_is_parse_error`, `too_small_interval_is_rejected`.
Changed to `scan_time`: `parses_valid_config`, `missing_field_is_parse_error`,
`unknown_field_is_parse_error` (typo `scan_tim`), `wrong_type_is_parse_error`
(a number), `load_reads_file_from_disk`.

New:

| Test | Checks |
|------|--------|
| `old_interval_seconds_is_parse_error` | A v0.1.x config is refused, and the message names `interval_seconds` |
| `valid_scan_times_are_accepted` | `00:00`, `02:00`, `02:30`, `23:59` → correct seconds of the day |
| `bad_scan_time_is_parse_error` | 10 bad strings (list above) → `Parse` error mentioning `HH:MM` |
| `scan_time_is_shown_as_utc` | `Display` is `"07:05 UTC"` |
| `next_scan_is_later_today_or_tomorrow` | 01:00 → today 02:00; 01:59:59 → 1 s later; exactly 02:00:00 → tomorrow; 14:00 → tomorrow |
| `next_scan_around_midnight` | `00:00` at midnight → next day; one second before midnight → midnight; `23:59` |
| `next_scan_is_never_more_than_a_day_away` | Over two days in steps of 1789 s: always in the future, at most 24 h, always at 02:00 |
| `sleep_until_past_time_returns_at_once` | A target in the past doesn't sleep |
| `wait_is_formatted_in_hours_and_minutes` | `format_wait` output |

### Master — 133 tests (was 132)

New: `daily_agent_is_stale_only_after_a_missed_scan`. An agent last seen
24 h 10 min ago (a slightly late daily scan) is not stale; one last seen
26 h ago is. The existing threshold tests use the constant, so they still
check that the limit is exclusive.

## Checks

Development machine (Fedora), rustc **1.99.1**:

| Check | Agent | Master |
|-------|-------|--------|
| `cargo test --locked` | ✅ 42 passed | ✅ 133 passed |
| `cargo clippy --all-targets --all-features --locked -- -D warnings` | ✅ | ✅ |
| `cargo fmt --check` | ✅ | ✅ |
| `cargo build --release --locked` | ✅ 3,202,936 bytes (v0.1.1: 3,209,176) | — |

### Manual run of the schedule

Release binary, `scan_time` set two minutes ahead (`11:55`), all three
modules, against a small fake master on `127.0.0.1` that answers 200 and
logs each POST. Run for 120 s, times in UTC:

```text
11:53:39 lunarscope-agent 0.2.0 started: modules [ssh_scan, firewall_scan, package_scan], daily scan at 11:55 UTC, master http://127.0.0.1:38111
11:53:39 scan cycle: 3 finding(s) in 6 ms; accepted 3, rejected 0, not sent 0
11:53:39 next scan at 11:55 UTC (in 0 h 01 min)
11:55:00 scan cycle: 3 finding(s) in 8 ms; accepted 3, rejected 0, not sent 0
11:55:00 next scan at 11:55 UTC (in 24 h 00 min)
```

Fake master: 3 POSTs at 11:53:39 and 3 at 11:55:00. So the startup scan
runs, the scheduled scan runs within the same second as `scan_time`, it
doesn't run twice, and the next one is set 24 h later.

The two error messages above (old `interval_seconds` key and `"2:00"`) were
also produced with this binary; both exit with code 1.

Not tested: a real 24 h wait, and the 10-minute re-check after a clock
change. The latter only matters on VMs that are suspended or have a large
clock correction.

## Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| `next_scan`: `today > now` → `>=` (runs twice at the scan time) | `next_scan_is_later_today_or_tomorrow`, `next_scan_around_midnight` |
| `next_scan`: tomorrow + 1 h | the three `next_scan_*` tests |
| `sleep_until` waits 1000 s past the target | `sleep_until_past_time_returns_at_once` |
| Digit check removed (`"+1:00"` accepted) | `bad_scan_time_is_parse_error` |
| Hour 24 allowed | `bad_scan_time_is_parse_error` |
| Minutes ignored in `seconds_of_day` | `valid_scan_times_are_accepted`, `next_scan_around_midnight` |
| `UTC` missing from `Display` | `scan_time_is_shown_as_utc` |
| Master: `STALE_AFTER_SECONDS` back to `2 * 3600` | `daily_agent_is_stale_only_after_a_missed_scan` |
| Master: `STALE_AFTER_SECONDS` = `48 * 3600` | `daily_agent_is_stale_only_after_a_missed_scan` |

All 9 caught. The `.max(next)` in the loop and the 10-minute sleep steps are
not covered by a unit test (they would need a fake clock). The manual run
covers the normal case.

## Docs updated

- [code-overview.md](code-overview.md): describes 0.2.0.
- Steps 12, 13, 17, 18, 19 and [testing.md](testing.md) (agent), steps 29
  and 30 (master): a short "Update 2026-11-09" note pointing here. The
  original text and evidence were left as they were, because they record
  what was built and tested then.
- [README](../README.md): link to this file.

## Files to commit

`lunarscope-agent` (together with the uncommitted edits already in the
working tree: `cybermoon.nl` URLs and comment changes):

```text
Cargo.toml
Cargo.lock
config.toml
scripts/measure.sh
src/config.rs
src/main.rs
src/sender.rs
```

`lunarscope-master`: committed together with the dashboard login, see
[change-0.2.0-dashboard-login.md](../phase-3-lunarscope-master/change-0.2.0-dashboard-login.md).

## Commit and tag (done by hand)

> **Update 2026-11-16:** Not committed separately. Agent 0.2.0 is released
> together with 0.3.0, where `scan_time` moved from `config.toml` to the
> master; use the commands in [change-0.3.0-agent-management.md](../phase-3-lunarscope-master/change-0.3.0-agent-management.md). The commands below are kept for the
> record.

Agent, from `repos/lunarscope-agent`:

```bash
git add Cargo.toml Cargo.lock config.toml scripts/measure.sh src
git status
git commit -m "Scan once a day at scan_time (UTC) instead of every interval_seconds (v0.2.0)"
git pull --rebase origin main
git tag -a v0.2.0 -m "lunarscope-agent v0.2.0"
git push origin main
git push origin v0.2.0
```

Master: see [change-0.2.0-dashboard-login.md](../phase-3-lunarscope-master/change-0.2.0-dashboard-login.md) (one commit, tag `v0.2.0`).

Docs, from `repos/lunarscope-docs`:

```bash
git add building-phase
git status
git commit -m "Document agent v0.2.0 (daily scan time), master v0.2.0 (login, 25 h stale limit) and code overviews"
git push origin main
```
