# Step 24 — Database connection

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

`async fn init_db(path: &str) -> SqlitePool` in `src/db/mod.rs`, called in
`main()`, with the pool passed to axum as state.

## What was done

### `src/db/mod.rs`

```rust
pub async fn init_db(path: &Path) -> Result<SqlitePool, DbError> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        // WAL lets the dashboard read while agents' results are written.
        .journal_mode(SqliteJournalMode::Wal)
        // Safe with WAL: a power cut can lose the last commits, not corrupt.
        .synchronous(SqliteSynchronous::Normal)
        .foreign_keys(true)
        .busy_timeout(BUSY_TIMEOUT);           // 5 s

    let pool = SqlitePoolOptions::new()
        .max_connections(MAX_CONNECTIONS)      // 5
        .connect_with(options)
        .await
        .map_err(DbError::Open)?;
    run_migrations(&pool).await.map_err(DbError::Migrate)?;
    Ok(pool)
}
```

Also new: `DbError` (`Open` / `Migrate`, with `Display`) and
`agent_count(pool)`, used for the startup log line. The temporary
`allow(dead_code)` on `run_migrations` from step 23 was removed, because it is
now used by `init_db`.

### `src/main.rs`

```rust
#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
}

fn app(state: AppState) -> Router {
    Router::new().with_state(state)   // routes follow in steps 25–31
}
```

`run()` parses the arguments, calls `init_db`, builds `AppState`, logs one
line and builds the router:

```text
lunarscope-master 0.1.0: database /var/lib/lunarscope/master.db ready, 0 registered agent(s)
```

Binding to `0.0.0.0:3000` and serving the router follows in **step 32**, so for
now the binary starts, prepares the database and exits.

| Argument | Default | |
|----------|---------|---|
| `--db <path>` | `/var/lib/lunarscope/master.db` | SQLite file |

`main()` turns errors into one line and exit code 1, as in the agent
(step 18).

## Choices and justification

- **`Result<SqlitePool, DbError>` instead of a bare `SqlitePool`** (a small
  deviation from the guide's signature). Opening can fail (directory missing,
  no permission, file is not a database, changed migration). The master
  should then stop with a clear message instead of panicking.
- **`&Path` instead of `&str`** — it is a file path, so `Path` is the right
  type; `--db` gives a `PathBuf`.
- **Default `/var/lib/lunarscope/master.db`** — the directory the architecture
  document reserves for state (`ReadWritePaths=/var/lib/lunarscope`, 6.4). The
  architecture also mentions a `--config /etc/lunarscope/master.toml`. The
  master only needs one setting so far, so a `--db` argument is enough. If
  steps 32–33 need more settings (listen address, …), a config file can be
  added then.
- **WAL journal mode** — in the default mode a write locks the whole file,
  so dashboard reads would wait for agents' inserts and the other way around.
  With WAL, readers and one writer work at the same time. It creates
  `master.db-wal` and `master.db-shm` next to the database, which is why the
  whole directory must be writable (systemd `ReadWritePaths`, not just the
  file).
- **`synchronous = NORMAL`** — the recommended setting with WAL: much faster
  writes, and a crash or power cut can only lose the most recent commits; it
  cannot corrupt the database. Losing the last few findings is acceptable,
  because agents send fresh ones every interval.
- **`foreign_keys(true)`** — SQLite turns foreign keys off by default on
  every connection. sqlx enables them by default too, but writing it out
  makes the dependency on it visible (`ON DELETE CASCADE`, step 23).
- **`busy_timeout` 5 s** — if another connection holds the write lock, a query
  waits up to 5 s instead of failing at once with "database is locked". This
  is also sqlx's default (`sqlx-sqlite` `options/mod.rs`:
  `busy_timeout: Duration::from_secs(5)`). It is written out so the value is
  visible and doesn't change silently with a future sqlx version.
- **5 connections** — SQLite allows only one writer at a time anyway, so a
  large pool doesn't help. A few connections let dashboard reads run in
  parallel with a write.
- **`AppState` struct instead of passing `SqlitePool` directly** — handlers
  take `State<AppState>`. Later shared things (e.g. the Tera instance in
  step 28) become extra fields without changing every handler signature.
  `SqlitePool` is a cheap handle, so `Clone` on the state costs nothing.

## Checks

### Unit tests

New in `src/db/mod.rs` (with a `TempDb` helper: a unique temp directory that
is removed on drop, including `-wal`/`-shm`):

| Test | Checks |
|------|--------|
| `init_db_creates_file_and_schema` | File doesn't exist → created, tables present and empty |
| `init_db_keeps_data_across_restarts` | Close and reopen: agent and result still there (migrations don't wipe data) |
| `init_db_sets_connection_options` | `journal_mode = wal`, `foreign_keys = 1`, `synchronous = 1` (NORMAL), `busy_timeout = 5000` |
| `init_db_enforces_foreign_keys_on_every_connection` | All 5 pool connections held at once; each has `foreign_keys = 1` |
| `init_db_fails_for_missing_directory` | `DbError::Open`, message "could not open database…" |
| `init_db_refuses_a_changed_migration` | Stored checksum altered → `DbError::Migrate` |
| `init_db_refuses_a_file_that_is_not_sqlite` | A text file at the path → error |

New in `src/main.rs`. These use `tower::ServiceExt::oneshot` to send a
request through the router without opening a port; `tower` was added as a
**dev-dependency** only:

| Test | Checks |
|------|--------|
| `default_db_path`, `db_path_from_argument`, `bad_args_are_errors` | Argument parsing |
| `handlers_can_use_the_pool_from_state` | A test route with `State<AppState>` reads the agent count from the database through the router → `200 "1"` |
| `app_without_routes_answers_404` | The router works with no routes yet |

Total: **26 tests** (14 from step 23 + 12 new), all passing.

### Mutation checks

| Change | Failing tests |
|--------|---------------|
| journal mode `Delete` instead of `Wal` | `init_db_sets_connection_options` |
| `foreign_keys(false)` | `init_db_sets_connection_options`, `init_db_enforces_foreign_keys_on_every_connection` |
| `run_migrations` removed from `init_db` | `init_db_creates_file_and_schema`, `init_db_keeps_data_across_restarts`, `init_db_refuses_a_changed_migration` |
| `create_if_missing(false)` | 5 tests (every test that starts from an empty directory) |
| `.busy_timeout(...)` removed | **none** — expected: sqlx's default is the same 5 s, so behaviour doesn't change. The test pins the value, so a future change of the default would be noticed |

### Running the binary

```text
$ lunarscope-master --db ./master.db        # first start
lunarscope-master 0.1.0: database ./master.db ready, 0 registered agent(s)
exit=0                                       # creates master.db, master.db-shm, master.db-wal

$ lunarscope-master --db ./master.db        # second start: same, no error
exit=0

$ sqlite3 master.db .tables 'PRAGMA journal_mode;' 'SELECT version, description, success FROM _sqlx_migrations;'
_sqlx_migrations  agents            scan_results
wal
1|initial|1

$ lunarscope-master --db /nonexistent/dir/master.db
lunarscope-master: could not open database: error returned from database: (code: 14) unable to open database file (/nonexistent/dir/master.db)
exit=1

$ lunarscope-master --port 80
lunarscope-master: unknown argument '--port'
usage: lunarscope-master [--db <path>]
exit=1
```

```text
$ cargo test                                → 26 passed, 0 failed
$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
$ cargo build                               → no warnings
```

## Next step

Step 25 — `POST /api/scan-result`.
