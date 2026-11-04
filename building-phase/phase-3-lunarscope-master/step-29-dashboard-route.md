# Step 29 — Dashboard route: `GET /`

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

`src/routes/dashboard.rs`: query the latest scan results per agent, render
them with Tera, and return the HTML.

## What was done

### Files

| File | Change |
|------|--------|
| `src/routes/dashboard.rs` | New — handler `dashboard`, `summaries()` (rows → view, sorting, stale), `worst()`, 12 tests |
| `src/time.rs` | New — `unix_now()` (moved from `api.rs`), `format_utc()`, 3 tests |
| `migrations/0002_latest_results.sql` | New — `latest_results` table + backfill |
| `src/db/queries.rs` | `agent_overviews()`; `insert_scan_result()` also updates `latest_results` |
| `src/db/mod.rs` | 5 tests for migration 2 |
| `src/main.rs` | Route `GET /`; the step 24 test "`GET /` is 404" became "unknown path is 404" |
| `src/templates.rs` | Temporary `allow(dead_code)` from step 28 removed |

### What "latest results per agent" means

An agent sends one result per check every cycle. The dashboard shows, per
agent, the **newest result of every check** (`scan_type` + `check_name`) and
counts those per severity. Example: `ssh_permit_root_login` was **High** at
10:00 and **Pass** at 11:00 → it counts as one Pass, not as one High and one
Pass.

### Handler

```rust
pub async fn dashboard(State(state): State<AppState>)
    -> Result<Html<String>, (StatusCode, &'static str)>
{
    let rows = queries::agent_overviews(&state.db).await.map_err(/* log, 500 */)?;
    let now = unix_now();
    let view = DashboardView { generated_at: format_utc(now), agents: summaries(rows, now) };
    templates::render(&state.templates, "dashboard.html", &view)
}
```

`summaries()` turns each database row into an `AgentSummary` (step 28):

| Field | Rule |
|-------|------|
| `counts` | Number of checks per severity (from the newest result of each check) |
| `worst` | Most severe level with a count > 0; `None` if the agent never reported |
| `last_seen` | `YYYY-MM-DD HH:MM UTC`, or `never` |
| `stale` | `last_seen` more than **2 h** ago (`STALE_AFTER_SECONDS`: two missed cycles at the default 1 h interval) |
| order | Worst first: Critical, High, Medium, Low, Pass, never reported; then by hostname |

### Time formatting

Tera 2 has no date filter (step 28), so `time::format_utc()` formats Unix
seconds in Rust. It uses Howard Hinnant's `civil_from_days` algorithm (20
lines) instead of adding a date crate (`chrono`/`time`) for one function.
Times are shown in **UTC**: the master runs on a VPS, and admins may be in
different time zones. "UTC" is printed so nobody mistakes it for local time.

## Design change: the `latest_results` table

### First version: one query over the whole history

The first implementation computed "newest result per check" from
`scan_results` with a window function:

```sql
WITH latest AS (
    SELECT agent_id, severity,
           ROW_NUMBER() OVER (PARTITION BY agent_id, scan_type, check_name
                              ORDER BY timestamp DESC, id DESC) AS rn
    FROM scan_results)
SELECT … FROM agents a LEFT JOIN latest l ON l.agent_id = a.id AND l.rn = 1 GROUP BY a.id
```

It passed all tests, but `scan_results` keeps **every** result forever
(architecture 4.3: no retention). It was measured on one year of realistic
data: **10 servers × 5 checks × hourly = 438,000 rows**
([evidence](evidence/step-29-query-performance.txt)):

| Variant | Time per dashboard load |
|---------|------------------------:|
| Window function over `scan_results` | **1.1 – 1.6 s** |
| Same + covering index `(agent_id, scan_type, check_name, timestamp, id, severity)` | 0.45 s |
| Separate `latest_results` table | **0.08 – 0.1 ms** |

The first two read and sort every stored row on every page load, so they get
slower every hour. With the HTMX refresh every 30 s (step 31) per open
browser tab, that becomes a constant load on the VPS. The query plan shows
why: `SCAN scan_results … USE TEMP B-TREE`, i.e. all rows, then sorted.

### Chosen: maintain the newest result per check when it arrives

```sql
-- Newest result per check, kept up to date on every insert (step 29).
-- The dashboard reads this small table instead of searching the whole,
-- ever-growing scan_results history on each page load.

CREATE TABLE latest_results (
    agent_id    TEXT    NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    scan_type   TEXT    NOT NULL,
    check_name  TEXT    NOT NULL,
    severity    TEXT    NOT NULL
                CHECK (severity IN ('Critical', 'High', 'Medium', 'Low', 'Pass')),
    description TEXT    NOT NULL,
    remediation TEXT,
    timestamp   INTEGER NOT NULL,
    PRIMARY KEY (agent_id, scan_type, check_name)
) STRICT;

-- Fill it from results stored before this migration.
INSERT INTO latest_results (agent_id, scan_type, check_name, severity, description, remediation, timestamp)
SELECT agent_id, scan_type, check_name, severity, description, remediation, timestamp
FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY agent_id, scan_type, check_name
        ORDER BY timestamp DESC, id DESC
    ) AS rn
    FROM scan_results
)
WHERE rn = 1;
```

`insert_scan_result()` (step 25) now also **upserts** into `latest_results`, in
the same transaction as the history insert:

```sql
INSERT INTO latest_results (…) VALUES (…)
ON CONFLICT (agent_id, scan_type, check_name) DO UPDATE SET
    severity = excluded.severity, description = excluded.description,
    remediation = excluded.remediation, timestamp = excluded.timestamp
WHERE excluded.timestamp >= latest_results.timestamp
```

- The dashboard reads at most *agents × checks* rows (50 here) through the
  primary key: `SEARCH l USING INDEX sqlite_autoindex_latest_results_1`. Its
  speed no longer depends on how much history exists.
- Cost: one extra upsert per finding, about **0.5 ms**.
- **`WHERE excluded.timestamp >= …`** — if a request with an *older*
  timestamp arrives late (retry, network delay), it is stored in the history
  but doesn't replace the newer result. A late "High" can't undo a fix that was
  already reported. With equal timestamps, the later insert wins, the same
  tie-break as `id DESC` before.
- **`scan_results` is unchanged** and still holds the full history (for the
  detail page and a future history view).
- The **backfill** in the migration fills `latest_results` from existing
  history, so a database created before this step is correct right after the
  upgrade. On the 438k-row database the real binary ran the migration in
  **1.38 s** (10.7 MB peak memory). This is a one-time cost at the first start
  of the new version.
- This is the "later schema changes become a new migration file" case
  anticipated in step 23. `0001_initial.sql` is untouched, as sqlx requires
  (changing an applied migration fails its checksum, step 24).

### Known limitation

If a module is **disabled** on an agent, its last result stays in
`latest_results` and keeps being counted. That is acceptable for the
prototype: the result is still the latest known state of that check, and
the detail page (step 30) shows how old it is. A fix later could be to hide
results older than a few intervals.

## Checks

### Unit tests

**`src/routes/dashboard.rs`** — test data is written through the real
`insert_scan_result()`, the same path the API uses:

| Test | Checks |
|------|--------|
| `empty_database_shows_empty_dashboard` | 200, `text/html`, "No agents have reported yet." |
| `only_the_newest_result_of_each_check_counts` | High then Pass for one check + Medium for another → counts Medium 1, Pass 1, badge Medium, no High badge |
| `older_result_arriving_late_does_not_replace_newer_one` | Pass at t=200, then High at t=100 → still Pass; history has both rows |
| `same_timestamp_newest_row_wins` | Two results with the same timestamp → the later one counts |
| `same_check_name_in_different_modules_counts_separately` | `ssh_scan/c` and `other_scan/c` are two checks |
| `results_of_agents_do_not_mix` | Counts per agent stay separate |
| `agent_without_results_is_listed` | Registered but silent agent: link, "never", "no results" |
| `dashboard_shows_last_seen_and_marks_stale_agents` | Formatted last-seen times; > 2 h → `class="stale"` |
| `summaries_are_sorted_worst_first_then_by_hostname` | 7 agents in the order Critical, High, Medium, Low, Pass (by name), never |
| `worst_is_the_most_severe_non_zero_count` | Medium / Critical / Pass / none |
| `stale_threshold_is_exclusive` | Exactly 2 h → not stale; 2 h + 1 s → stale; never reported → not stale |
| `database_failure_is_500` | Closed pool → 500 "internal server error" |

**`src/db/mod.rs`** (migration 2):

| Test | Checks |
|------|--------|
| `latest_results_table_has_expected_columns` | 7 columns, types, NOT NULL |
| `latest_results_has_one_row_per_check` | Second row for the same check → `UNIQUE` error |
| `latest_results_rejects_unknown_severity_and_agent` | `CHECK` and `FOREIGN KEY` |
| `migration_2_backfills_latest_results_from_history` | Database at version 1 (`MIGRATOR.run_to(1, …)`) with history → after upgrading, the newest result of each check is in `latest_results` |
| `deleting_an_agent_deletes_its_latest_results` | `ON DELETE CASCADE` |

**`src/time.rs`**:

| Test | Checks |
|------|--------|
| `formats_known_dates` | 1970-01-01, 2000-02-29, 2024-02-29 12:34, 2026-10-04 00:02, 2099-12-31 23:59 (expected values from Python's `datetime`) |
| `every_day_follows_the_previous_one` | 50 years day by day: every date is the next day, month lengths and leap years (incl. 2000) correct |
| `now_is_a_plausible_time` | Seconds, not milliseconds |

Total master tests: **102**, all passing.

### Mutation checks

| Bug introduced | Failing tests |
|----------------|---------------|
| upsert without `WHERE` (late older result overwrites) | `older_result_arriving_late_does_not_replace_newer_one` |
| `>` instead of `>=` in the upsert | `same_timestamp_newest_row_wins` |
| `latest_results` not updated on insert | 5 dashboard tests |
| `scan_type` not part of the key | `same_check_name_in_different_modules_counts_separately` |
| backfill takes the oldest result | `migration_2_backfills_latest_results_from_history` |
| `JOIN` instead of `LEFT JOIN` | `agent_without_results_is_listed`, `dashboard_shows_last_seen_and_marks_stale_agents` |
| sort order reversed | `summaries_are_sorted_worst_first_then_by_hostname` |
| stale at exactly 2 h | `stale_threshold_is_exclusive` |

(The first, window-function version was mutation-checked as well, before it
was replaced: oldest-instead-of-newest, missing id tie-break, missing
`scan_type` in the partition, counting all history, inner join, sorting and
stale threshold were all caught.)

```text
$ cargo test                                → 102 passed, 0 failed
$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

The page is rendered by the same template that was checked in a browser in
step 28. Opening `GET /` in a browser on the running master follows once it
listens on a port (step 32).

## Next step

Step 30 — server detail route `GET /server/:agent_id`.
