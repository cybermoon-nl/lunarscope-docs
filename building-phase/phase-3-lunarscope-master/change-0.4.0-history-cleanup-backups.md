# Change (0.4.0) — history cleanup and daily backups

**Repo:** `lunarscope-master` 0.4.0
**Date:** 2026-11-16
**Status:** Done — code, tests, mutation checks and an end-to-end test; not
committed yet

## Why

Every finding of every scan is stored in `scan_results` (the history).
With daily scans that table only grows, and nothing made a copy of the
database: a broken disk or a wrong `DELETE` would lose everything.

## What it does

A task inside the master runs **60 seconds after startup and then every 24
hours**:

1. **Cleanup:** deletes rows from `scan_results` older than `--keep-days`
   (default **90**; `0` keeps everything). `latest_results` — what the
   dashboard shows — is never touched, so a check that hasn't changed for
   months stays visible.
2. **Backup:** `VACUUM INTO '<dir>/master-YYYY-MM-DD.db'` — a consistent,
   compacted copy made while the master keeps running (no need to stop it).
   At most one per day: a restart on the same day doesn't make another.
3. **Rotation:** only the newest `--backups` files (default **7**; `0` = no
   backups) named `master-YYYY-MM-DD.db` are kept. Other files in the folder
   are left alone.

| Option | Default | Meaning |
|--------|---------|---------|
| `--keep-days <days>` | 90 | History older than this is deleted; 0 = keep all |
| `--backups <count>` | 7 | Daily backups to keep; 0 = none |
| `--backup-dir <path>` | `backups/` next to the database (`/var/lib/lunarscope/backups`) | Where they go |

Startup log: `maintenance: history kept 90 days, 7 daily backups in …`.
After each run: `maintenance: deleted N old history row(s), backup …, removed N old backup(s)`.
Errors are logged and the next run tries again; they never stop the master.

The default folder is inside the service's `StateDirectory`, so the
hardened unit (read-only system) can write there without changes. A backup
on the same disk protects against mistakes, not against a dead disk: copy
`/var/lib/lunarscope/backups` elsewhere (rsync, borg) for that.

To restore: stop the master, copy a backup over `master.db` (and delete
`master.db-wal` / `-shm`), start it.

## Code

| File | Change |
|------|--------|
| `src/maintenance.rs` (new) | `Maintenance {keep_days, backup_dir, backups}`, `run_once` (cleanup, backup, rotation; returns a `Report`), `rotate`, `spawn` (the 24-hour task; does nothing when both are off) |
| `src/main.rs` | The three options, defaults, startup line, `maintenance::spawn` |

## Tests

| Test | Checks |
|------|--------|
| `old_history_is_deleted_but_latest_results_stay` | Rows 100, 90 and 1 day old with `keep_days` 90: only the 100-day row is deleted (exactly 90 days stays); the remaining rows are the right ones; `latest_results` untouched |
| `keep_days_zero_keeps_everything` | Nothing deleted, empty report |
| `backup_is_a_working_copy_made_once_a_day` | File `master-2026-11-16.db` exists, opens as SQLite with the same rows; a second run the same day makes none |
| `only_the_newest_backups_are_kept` | With 2 kept: the oldest dated files deleted, an unrelated file in the folder kept |
| `zero_backups_makes_none` | No folder, no file |
| main `parse_args` tests | Options, defaults, bad numbers |

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| Deletes the **new** history instead (`>` for `<`) | `old_history_is_deleted_but_latest_results_stay` — only after the test also checked *which* rows remain (with 3 rows, deleting the 1-day row instead gave the same counts) |
| A second backup on the same day | `backup_is_a_working_copy_made_once_a_day` |
| One backup too many kept | `only_the_newest_backups_are_kept` |

3 of 3 caught.

## End-to-end test

Temporary master (`--keep-days 90 --backups 2 --backup-dir …/backups`): one
minute after startup the log said
`maintenance: deleted 0 old history row(s), backup …/backups/master-2026-11-16.db`;
the file opened with Python's `sqlite3` and held the one agent.
