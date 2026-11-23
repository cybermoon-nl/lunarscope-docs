# Change (0.4.0) — time zone in a Settings page

**Repos:** `lunarscope-master` 0.4.0, `lunarscope-agent` 0.4.0
**Date:** 2026-11-16
**Status:** Done — code, tests, mutation checks and an end-to-end test; not
committed yet

## Why

Since 0.2.0 everything was UTC: times on the pages, and the daily scan time
(`02:00` meant 02:00 UTC, which is 03:00 or 04:00 in the Netherlands). The
user asked for the time zone to be a setting in the web UI, applied to
**both** what the pages show and the scan times ("Display + scan times").

## What it does

**Settings → General** (admins only) has a list of all IANA time zones
(`Europe/Amsterdam`, `UTC`, …) and shows the current time in the chosen
one. Saving takes effect at once, without a restart, and writes an audit
line `time zone set`.

- **Pages:** every time is shown in that zone with its abbreviation:
  `2026-11-16 21:23 CET` (summer: `CEST`). Dates (report) too.
- **Scan times:** the "Daily scan" time of each agent is now a **local**
  time in that zone. The agent still works in UTC: `GET /api/agent-config`
  sends it the **UTC time of the next occurrence** of that local time.
  `02:00` Amsterdam becomes `01:00` in winter and `00:00` in summer.

The zone database is built into the master (`jiff` with
`tzdb-bundle-always`), so it doesn't depend on the server's `tzdata`. A
zone name in the database that this build doesn't know (e.g. after
downgrading) falls back to UTC with a log line.

### Summer and winter time

The UTC time an agent gets is calculated for its **next** scan, so it
changes by itself on the day the clocks change. The agent notices at its
next check-in. Before 0.4.0 the agent would treat any change as "new
configuration" and scan at once; that would mean an extra scan twice a
year for nothing. So the agent now tells the two apart:

| What changed in the fetched configuration | Agent (`compare` → `Wake`) |
|-------------------------------------------|----------------------------|
| `version` (scans switched, Scan now, …) | `NewConfig`: scan now |
| Only `scan_time` (UTC) | `NewScanTime`: log `scan time changed to 00:00 (master's time zone), no scan now`, wait for the new time |
| Nothing | Keep waiting |

A local time that doesn't exist on a given day (in the hour skipped in
spring) or exists twice (autumn) is resolved with `jiff`'s default
"compatible" rule: moved forward past the gap, or the first of the two.
Only scan times between 02:00 and 03:00 are affected; there's no test for
this edge.

## Code

| Repo | File | Change |
|------|------|--------|
| master | `migrations/0004_users_settings_updates.sql` | `settings(key, value)` with `timezone = 'UTC'` |
| master | `src/settings.rs` (new) | `Settings {timezone_name, timezone}`, `time_zone(name)`, `time_zone_names()`, `load` (falls back to UTC), `save_timezone` |
| master | `src/time.rs` | `format_in(unix, tz)`, `date_in`, `next_local_as_utc(local, tz, now)` |
| master | `src/main.rs` | `AppState.settings: Arc<RwLock<Settings>>`, `state.settings()`; loaded at startup (`time zone Europe/Amsterdam` in the log) |
| master | `src/templates.rs` | `Ui` carries the zone: `ui.time()`, `ui.date()`; templates get `tz_name` |
| master | `src/routes/settings.rs` (new) + `templates/settings.html`, `settings_tabs.html` | The page and tabs (General, Users, Agent updates, Audit log) |
| master | `src/routes/api.rs` | `agent_config` converts the scan time |
| master | all pages | `format_utc` → `ui.time()`; "Daily scan (UTC)" labels show the zone |
| agent | `src/main.rs` | `Wake::NewScanTime`, `compare()` |

Dependency added to the master: `jiff` 1.0.0.

## Tests

| Test | Checks |
|------|--------|
| `times_are_shown_in_the_chosen_zone` | Same instant as `… CET` / `… CEST` / `… UTC` |
| `local_scan_time_becomes_utc_for_the_next_scan` | 02:00 Amsterdam = 01:00 UTC on 16 November, 00:00 UTC on 1 July; UTC unchanged |
| `the_switch_to_winter_time_is_taken_from_the_next_scan_date` | On Saturday 24 October 2026 (still summer) the next 03:00 is Sunday after the switch → 02:00 UTC; the next 12:00 is still Saturday → 10:00 UTC |
| `malformed_local_times_give_none` | `""`, `2`, `24:00`, `02:60`, `aa:bb` |
| `starts_in_utc_and_keeps_a_saved_zone`, `unknown_zone_in_the_database_falls_back_to_utc`, `known_zones` | Settings storage |
| `page_shows_the_zones_with_the_current_one_selected` | The list, current zone selected |
| `saving_a_zone_changes_times_and_scan_times` | 303 to `?saved=1`; in memory and in the database; the agent config's `scan_time` is the converted time; pages show `CET`/`CEST` |
| `unknown_zone_is_refused` | 400 "unknown time zone", zone stays UTC |
| agent `new_version_means_scan_now_new_time_only_means_wait` | The `Wake` table above |

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| Scan time sent as local time, not converted to UTC | 3 tests |
| Pages show UTC instead of the zone | 2 tests |
| New zone only used after a restart (not stored in `AppState`) | `saving_a_zone_changes_times_and_scan_times` |
| Agent scans when only the UTC scan time changed | `new_version_means_scan_now_new_time_only_means_wait` |

4 of 4 caught.

## End-to-end test

Temporary master, Settings → `Europe/Amsterdam`: `303 /settings?saved=1`,
page shows `Saved.`, the zone selected and `2026-11-16 21:23 CET`. An agent
added with "Daily scan" `02:00` logged
`configuration version 1: scans [...], daily scan at 01:00 UTC`. The audit
log lines were shown in CET.

> **Update (0.5.0):** the default is now **Europe/Amsterdam** instead of UTC
> (also for databases that still had the old UTC default). See
> [change-0.5.0-ui-feedback.md](change-0.5.0-ui-feedback.md#addition-europeamsterdam-as-the-default-time-zone).
