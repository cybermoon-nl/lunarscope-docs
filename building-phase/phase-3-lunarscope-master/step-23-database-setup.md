# Step 23 — Database setup

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

`src/db/mod.rs` with `CREATE TABLE agents (...)` and `CREATE TABLE
scan_results (...)` as migrations, run with `sqlx::migrate!()` or by hand at
startup.

## What was done

### Files

| File | Change |
|------|--------|
| `migrations/0001_initial.sql` | New — the schema |
| `src/db/mod.rs` | New — embedded migrator, `run_migrations()`, 14 tests |
| `build.rs` | New — rebuild when a migration changes |
| `src/main.rs` | `mod db;` |

### `migrations/0001_initial.sql`

```sql
-- Initial schema (architecture document, chapter 4.2).

CREATE TABLE agents (
    id           TEXT    PRIMARY KEY,          -- UUID of the agent
    hostname     TEXT    NOT NULL,             -- hostname of the monitored server
    api_key_hash TEXT    NOT NULL UNIQUE,      -- hash of the pre-shared API key, never the key itself
    created_at   INTEGER NOT NULL,             -- registration time (Unix seconds)
    last_seen    INTEGER                       -- last accepted request (Unix seconds), NULL until then
) STRICT;

CREATE TABLE scan_results (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id    TEXT    NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    scan_type   TEXT    NOT NULL,              -- module name, e.g. ssh_scan
    check_name  TEXT    NOT NULL,              -- check within the module
    severity    TEXT    NOT NULL
                CHECK (severity IN ('Critical', 'High', 'Medium', 'Low', 'Pass')),
    description TEXT    NOT NULL,
    remediation TEXT,                          -- NULL when nothing needs fixing
    timestamp   INTEGER NOT NULL               -- scan time sent by the agent (Unix seconds)
) STRICT;

-- Dashboard and detail page look up results per agent, newest first.
CREATE INDEX scan_results_agent_time ON scan_results (agent_id, timestamp);
```

### `src/db/mod.rs`

```rust
/// All files in `migrations/`, embedded in the binary at compile time.
pub static MIGRATOR: Migrator = sqlx::migrate!();

/// Brings the database schema up to date. Already applied migrations are
/// skipped, so this is safe to run at every startup.
pub async fn run_migrations(pool: &SqlitePool) -> Result<(), MigrateError> {
    MIGRATOR.run(pool).await
}
```

`run_migrations` is called from `init_db()` in step 24. Until then it is only
used by the tests, so it carries a temporary
`#[cfg_attr(not(test), allow(dead_code))]`, which step 24 removes.

### `build.rs`

```rust
fn main() {
    println!("cargo:rerun-if-changed=migrations");
}
```

## Choices and justification

### `sqlx::migrate!()` instead of running SQL by hand

- The SQL files are **embedded in the binary**, so deployment stays a single
  file. No `migrations/` directory is needed on the VPS.
- sqlx records each applied migration (version + checksum) in the
  `_sqlx_migrations` table. At startup only new migrations run, and a migration
  that was **changed** after being applied is refused (checksum mismatch). Later
  schema changes become a new file `0002_….sql` instead of hand-written "does
  this column exist yet?" code.
- **`build.rs`** — `migrate!()` reads the files during compilation, but cargo
  only rebuilds when Rust files change. Without the `rerun-if-changed` line, an
  edit to a `.sql` file could silently leave the **old** schema in the binary.
  The sqlx documentation recommends exactly this.

### Schema compared with the architecture document (4.2)

The tables and columns are those of the architecture document. Changes:

| Change | Why |
|--------|-----|
| `api_key` → **`api_key_hash`** | The architecture document itself says the key "gets saved hashed". The column name now says what it contains, so nobody puts a plain key in it. The hash choice follows in step 26/27 (see note below). |
| **`STRICT`** tables | Plain SQLite tables accept any type in any column (e.g. the text `'yesterday'` in `timestamp`) and even `NULL` in a `TEXT PRIMARY KEY`. STRICT tables (SQLite ≥ 3.37; bundled 3.51.3) reject both. |
| **`CHECK (severity IN ('Critical','High','Medium','Low','Pass'))`** | Exactly the values `lunarscope-modules` produces (step 2). A wrong value, e.g. lowercase `high` (the architecture's API table mentions lowercase), is refused by the database itself, so the dashboard's sorting can rely on it. |
| **`ON DELETE CASCADE`** on `scan_results.agent_id` | The architecture document says a key is revoked by "a direct change in the database". Deleting an agent then also removes its results, instead of failing on the foreign key or leaving orphaned rows. |
| **Index `(agent_id, timestamp)`** | The dashboard (latest results per agent, step 29) and the detail page (all results of one agent, step 30) both filter on `agent_id` and sort by time. Without the index every page load scans the whole table, which only grows (no retention, architecture 4.3). |
| Trailing comma removed | The architecture's `CREATE TABLE scan_results` ends with `timestamp … NOT NULL, );`, which is a syntax error. |

**Note on `api_key_hash UNIQUE`.** `UNIQUE` is only meaningful if the same key
always gives the same hash, i.e. an **unsalted** hash such as SHA-256. That
is the plan for step 26/27. The API keys are 256-bit random values
(architecture 5.3), so they can't be guessed or looked up in a dictionary.
The slow, salted hashes from the architecture document (bcrypt/argon2) exist
to protect *human* passwords. On a key that is checked on every request they
would add tens of milliseconds per finding. The final decision and its
justification are documented in step 26/27. If argon2 is chosen after all,
`UNIQUE` is dropped in a new migration.

### Foreign keys are actually enforced

SQLite only enforces `REFERENCES` when `PRAGMA foreign_keys = ON` is set on
each connection. sqlx's `SqliteConnectOptions` turns it on by default. The
test `result_needs_an_existing_agent` checks that it really is on, so a later
change to the connection options (step 24) can't switch it off unnoticed.

### Compile-time checked queries

Step 22 said this would be decided in step 23. Step 23 only writes the
schema; the real queries come in step 25. The decision between
`sqlx::query!` (needs `DATABASE_URL` or a committed `.sqlx/` cache when
building) and runtime-checked `sqlx::query` with tests against the migrated
schema is therefore moved to **step 25**.

### sqlx 0.9: no SQL built with `format!`

sqlx 0.9 only accepts SQL as a string literal unless it is wrapped in
`AssertSqlSafe(...)`. The compiler stops with *"dynamic SQL strings should be
audited for possible injections"*. This protects the master against SQL
injection by design. The two test helpers that need a table name in the SQL
use `AssertSqlSafe`, with a comment that the name is a fixed test value.
Production code will only use literals with `?` parameters.

## Checks — unit tests (`src/db/mod.rs`)

Every test uses a fresh **in-memory** SQLite database with the migrations
applied, limited to one connection, because each new connection to
`sqlite::memory:` would be a different, empty database.

| Test | Checks |
|------|--------|
| `agents_table_has_expected_columns` | Names, types and NOT NULL of all 5 columns (via `PRAGMA table_info`) |
| `scan_results_table_has_expected_columns` | Same for all 8 columns |
| `migrations_can_run_again` | A second run (next startup) changes nothing and keeps data; `_sqlx_migrations` has one row per migration |
| `agent_id_must_be_unique` | Duplicate `id` refused |
| `agent_id_cannot_be_null` | `NULL` id refused (STRICT) |
| `api_key_hash_must_be_unique` | Two agents can't share a key hash |
| `result_needs_an_existing_agent` | Foreign key enforced (`FOREIGN KEY constraint failed`) |
| `all_module_severities_are_accepted` | All 5 values from `lunarscope-modules` |
| `other_severity_values_are_rejected` | `high`, `HIGH`, `Info`, empty → `CHECK constraint failed` |
| `remediation_is_optional` | `NULL` remediation stored and read back as `None` |
| `required_columns_reject_null` | `check_name = NULL` refused |
| `strict_tables_reject_wrong_types` | Text in `timestamp` refused (`cannot store TEXT value in INTEGER column`) |
| `deleting_an_agent_deletes_its_results` | Only that agent's results disappear |
| `results_lookup_per_agent_uses_the_index` | `EXPLAIN QUERY PLAN` of "results of one agent, newest first" uses `scan_results_agent_time` |

While writing the tests, `agents_table_has_expected_columns` first failed:
it expected `id` to allow NULL (as in normal SQLite tables), but in a STRICT
table a `TEXT PRIMARY KEY` is NOT NULL. The expectation was corrected and
`agent_id_cannot_be_null` was added.

### Mutation checks

Each change was made to `0001_initial.sql` and reverted. These runs also
show that `build.rs` works: every SQL edit was picked up without touching a
Rust file.

| Change to the schema | Failing tests |
|----------------------|---------------|
| `STRICT` removed | `agents_table_has_expected_columns`, `agent_id_cannot_be_null`, `strict_tables_reject_wrong_types` |
| severity `CHECK` removed | `other_severity_values_are_rejected` |
| `ON DELETE CASCADE` removed | `deleting_an_agent_deletes_its_results` |
| foreign key removed | `result_needs_an_existing_agent`, `deleting_an_agent_deletes_its_results` |
| `UNIQUE` on `api_key_hash` removed | `api_key_hash_must_be_unique` |
| index removed | `results_lookup_per_agent_uses_the_index` |

### Results

```text
$ cargo test
test result: ok. 14 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

## Later changes

- **Step 29** added `migrations/0002_latest_results.sql` (a `latest_results`
  table with the newest result per check) for dashboard performance. This
  file was not changed.

## Next step

Step 24 — database connection: `init_db(path) -> SqlitePool`, called in
`main()` and passed to axum as state.
