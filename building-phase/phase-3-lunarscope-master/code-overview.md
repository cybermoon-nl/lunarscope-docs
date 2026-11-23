# lunarscope-master — code overview

**Repo:** `lunarscope-master`
**Version described:** 0.5.0 (additions in sections 19 and 20); 0.3.0 (new GUI, agent management and rule scans from
[change-0.3.0-agent-management.md](change-0.3.0-agent-management.md);
dashboard login from [change-0.2.0-dashboard-login.md](change-0.2.0-dashboard-login.md);
25 h stale limit from
[change-0.2.0-daily-scan-time.md](../phase-2-lunarscope-agent/change-0.2.0-daily-scan-time.md))
**Date:** 2026-11-11, updated 2026-11-16

A walk through the master's code: what each file does, how the parts fit
together, and where to look when you want to change something. The step
files (22–34) explain *why* things were built this way; this file explains
*what is there*. The agent side is described in
[the agent code overview](../phase-2-lunarscope-agent/code-overview.md).

## 1. What the master does

The master is one Rust program on one server. It:

1. receives scan results from the agents (`POST /api/scan-result`), checks
   the API key and stores them in **SQLite**,
2. lets the administrator register new agents (`POST /api/register-agent`),
   which returns an agent id and API key,
3. serves a web **dashboard** behind a **password login**, in English or
   Dutch: findings of all servers with filters, a page per server, an
   **Agents** page, a **Scans** page and a weekly **Report**,
4. **manages the agents**: which scans each one runs and when. Agents fetch
   this with `GET /api/agent-config`, so a change needs no reinstall,
5. lets the administrator write **rule scans** (checks as data, in TOML)
   that are sent to the agents with their configuration,
6. hands out **install links**: "Add agent" gives a one-time
   `curl … | sudo bash` command that installs the agent on a new server.

It speaks plain HTTP on `127.0.0.1:3000`. A TLS reverse proxy in front of it
(on port 443) handles https for the agents and the browser (step 32).

```text
agents ──HTTPS──▶ reverse proxy :443 ──HTTP──▶ lunarscope-master 127.0.0.1:3000 ──▶ SQLite
browser ─HTTPS──▶                                                              /var/lib/lunarscope/master.db
```

## 2. Files

| File | Lines | What it is |
|------|------:|------------|
| `Cargo.toml` | 27 | Crate metadata and dependencies |
| `build.rs` | 5 | Rebuilds when a `.sql` file in `migrations/` changes |
| `migrations/0001_initial.sql` | 24 | Tables `agents` and `scan_results` |
| `migrations/0002_latest_results.sql` | 27 | Table `latest_results` (newest result per check) |
| `migrations/0003_agent_management.sql` | 58 | Scans, scans per agent, install links, scan time, change tracking |
| `src/main.rs` | ~680 | Entry point: arguments, `hash-password`, `AppState`, router, server, shutdown |
| `src/auth.rs` | ~370 | API keys, admin token, the `AuthenticatedAgent` and `Admin` extractors |
| `src/session.rs` | ~300 | Dashboard password (Argon2), sessions, lockout after wrong passwords |
| `src/error.rs` | 50 | `ApiError`: JSON error answers |
| `src/models.rs` | 55 | `Severity` |
| `src/time.rs` | 94 | Unix time, `YYYY-MM-DD HH:MM UTC` and `YYYY-MM-DD` formatting |
| `src/i18n.rs` | ~430 | English and Dutch texts, language cookie, `GET /lang/{en,nl}` |
| `src/rule_scans.rs` | ~380 | Reading and checking rule scans (TOML) and their JSON for agents |
| `src/db/mod.rs` | ~710 | Opening the database, migrations (and most database tests) |
| `src/db/queries.rs` | ~570 | All SQL queries |
| `src/routes/api.rs` | ~1030 | `POST /api/scan-result`, `POST /api/register-agent`, `GET /api/agent-config` |
| `src/routes/dashboard.rs` | ~820 | `GET /` with filters, "since previous scan", the stale rule |
| `src/routes/server.rs` | ~460 | `GET /server/{agent_id}` |
| `src/routes/agents.rs` | ~740 | Agents page, scan switches, scan time, delete, "Add agent" |
| `src/routes/install.rs` | ~380 | `GET /install/{token}` (install script), `GET /downloads/lunarscope-agent` |
| `src/routes/scans.rs` | ~340 | Scans page, rule scan editor, save, delete |
| `src/routes/report.rs` | ~200 | `GET /report`: risk score and tables |
| `src/routes/login.rs` | ~460 | `GET/POST /login`, `POST /logout`, the `require_login` middleware |
| `src/routes/static_files.rs` | ~110 | `GET /static/htmx.min.js`, `GET /static/app.js` |
| `src/templates.rs` | ~760 | Tera templates: loading, rendering with texts, HTMX fragments, shared view structs |
| `templates/*.html` | ~760 | `base` (layout and CSS), `findings_table` (part), and one per page |
| `static/htmx.min.js` | — | htmx 2.0.11, embedded in the binary |
| `static/app.js` | 78 | Details panel, delete confirmation, copy button |
| `install/lunarscope-agent.service` | 50 | Copy of the agent's unit, written by the install script |
| `lunarscope-master.service` | 51 | systemd unit with hardening |

Most of each `.rs` file is tests (`#[cfg(test)] mod tests` at the bottom).

### Dependencies (`Cargo.toml`)

| Crate | Used for |
|-------|----------|
| `axum` 0.8 | HTTP server and router |
| `tokio` (multi-threaded) | Async runtime, TCP listener, Ctrl-C / SIGTERM |
| `sqlx` 0.9 (`sqlite`, `migrate`, `macros`) | Database pool, queries, migrations embedded at compile time |
| `tera` 2 | HTML templates (auto-escapes, so a hostname like `<script>` is shown as text) |
| `serde`, `serde_json` | JSON bodies and template contexts |
| `sha2` | SHA-256 of API keys, the admin token, session tokens, install tokens and the agent binary |
| `argon2` 0.6 | Slow, salted hash of the dashboard password (Argon2id). Built with `opt-level = 3` in debug/test builds too, otherwise `cargo test` is slow |
| `getrandom` | Secure random bytes for new API keys and session tokens |
| `uuid` (`v4`) | New agent ids |
| `toml` 1.1 | Reading rule scans |
| `tower` (tests only) | Sending requests to the router without a real network |

Everything the master needs at runtime is in the binary: migrations,
templates, htmx and `app.js`. On disk are only the database, the secrets
(admin token file, dashboard password file) and the agent binary it hands
out (`--agent-binary`).

## 3. Database

Three tables (all `STRICT`, so SQLite checks the column types):

```text
agents                         scan_results (history)               latest_results (newest per check)
─────────────────────          ──────────────────────────           ─────────────────────────────────
id           TEXT PK  ◀──┬──── agent_id   TEXT  (cascade)    ┌──── agent_id    ┐
hostname     TEXT        │     id         INTEGER PK         │     scan_type   ├ PK
api_key_hash TEXT UNIQUE └──── …                             │     check_name  ┘
created_at   INTEGER           scan_type, check_name         │     severity, description,
last_seen    INTEGER NULL      severity (CHECK 5 values)     │     remediation, timestamp
                               description, remediation      │
                               timestamp                     └──── (also REFERENCES agents)
```

- **`agents`**: one row per registered agent. Only the **hash** of the API
  key is stored, never the key. `last_seen` is `NULL` until the first
  accepted result.
- **`scan_results`**: every finding ever received (the history). Index on
  `(agent_id, timestamp)`.
- **`latest_results`**: only the newest result of every check
  (`agent_id` + `scan_type` + `check_name`). The dashboard reads this small
  table instead of searching the whole history on every page load
  (migration 0002, step 29). The migration also fills it from existing
  history.
- `severity` may only be `Critical`, `High`, `Medium`, `Low` or `Pass`
  (`CHECK`), the same names as in `lunarscope-modules`.
- Times are Unix seconds (UTC) everywhere.

Added by migration 3 (v0.3.0):

| Table / column | What it holds |
|----------------|---------------|
| `agents.scan_time` | Daily scan time, `HH:MM` UTC (default `02:00`) |
| `agents.config_version` | Raised by one on every change for this agent; the agent compares it to see a change |
| `agents.checked_in` | Last `GET /api/agent-config` ("last check-in") |
| `scans` | Every scan the master knows: `builtin` (ssh/firewall/package, rows from the migration) or `rule` (with `source` TOML, `definition` JSON, `checks`) |
| `agent_scans` | Which scans are switched on per agent (cascade on agent and scan delete). A trigger gives a new agent all built-in scans |
| `install_tokens` | SHA-256 of one-time install tokens, their agent, expiry |
| `latest_results.previous_severity`, `since` | The severity before the last change (`NULL` = first result) and when the current one started; for "since previous scan" and "current status since" |

A latest result is **shown** when its scan is switched on for the agent, or
when the master doesn't know the scan type at all (results of older or
custom agents). Results of a switched-off scan are hidden, not deleted.

## 4. Flow through the program

### Startup

```text
main()                                    src/main.rs
 └─ run()
     ├─ "hash-password"? → hash_password_command(), then exit
     ├─ parse_args()                      --db, --listen, --admin-token-file, --password-file,
     │                                    --agent-binary, --public-url
     ├─ session::load_password_hash()     only with --password-file
     ├─ db::init_db()                     open/create SQLite, WAL, run migrations
     ├─ auth::load_admin_token()          only with --admin-token-file
     ├─ install::load_agent_binary()      only with --agent-binary (must be ELF, SHA-256)
     ├─ AppState::new() [.with_login()]   pool + admin token hash + templates [+ login]
     │                                    + agent binary + public URL
     ├─ print "database … ready, N registered agent(s), agent registration enabled|disabled,
     │        dashboard login enabled | dashboard locked (no --password-file),
     │        agent binary sha256 … | no agent binary"
     ├─ TcpListener::bind()               print "listening on http://…"
     └─ serve()                           until Ctrl-C / SIGTERM, then "stopped"
```

### A scan result from an agent

```text
POST /api/scan-result  (Authorization: Bearer lsk_…)
 ├─ body limit 64 KiB                     DefaultBodyLimit → 413
 ├─ AuthenticatedAgent extractor          auth.rs: hash key, look up agent → 401
 └─ api::scan_result()
     ├─ parse JSON                        → 400
     ├─ agent_id in body == key's agent   → 401
     ├─ validate() text fields            → 400
     ├─ timestamp within ±60 s            → 400 (replay protection)
     └─ queries::insert_scan_result()     one transaction:
          scan_results INSERT, latest_results UPSERT, agents hostname + last_seen
                                          → 200 (or 500 on a database error)
```

### A page in the browser

```text
GET /, /server/{id}, /agents, /scans, /report, … (every dashboard page)
 ├─ require_login middleware          routes/login.rs
 │    no --password-file              → 403 "not set up" page
 │    no / invalid session cookie     → 303 to /login (HTMX refresh: 401 + HX-Redirect: /login)
 ├─ query the database (agent_overviews / agent_by_id + latest_findings)
 ├─ build a view struct (counts, worst severity, stale, formatted times)
 └─ templates::render_page()
      normal request      → whole page
      HX-Request: true    → only the {% block findings %} (HTMX refresh every 30 s)
```

## 5. `src/main.rs`

### `AppState`

Shared by all handlers (axum clones it per request; it's cheap):

- `db`: the `SqlitePool`,
- `admin_token_hash`: SHA-256 of the admin token, or `None` (registration
  disabled),
- `templates`: the parsed Tera templates in an `Arc`,
- `login`: the dashboard login (`session::Login`: password hash, sessions,
  lockout), or `None` without `--password-file`, which locks the dashboard.
  `AppState::with_login(hash)` sets it,
- `agent_binary`: the binary install scripts download, with its SHA-256,
- `public_url`: how agents reach the master, for install commands.

`AppState::new` parses the embedded templates and panics on a syntax error.
The test `all_templates_parse` makes sure that can't reach a release.

### Arguments (`parse_args`)

| Argument | Default | Meaning |
|----------|---------|---------|
| `--db <path>` | `/var/lib/lunarscope/master.db` | SQLite file, created if missing |
| `--listen <addr:port>` | `0.0.0.0:3000` | Address to listen on. Production uses `127.0.0.1:3000` behind the proxy |
| `--admin-token-file <path>` | none | Enables agent registration |
| `--password-file <path>` | none | Argon2 hash of the dashboard password; without it the dashboard is locked |
| `--agent-binary <path>` | none | Agent binary for install scripts; read once at startup. Without it install links answer 503 |
| `--public-url <url>` | Host header | URL agents use to reach the master, e.g. `https://lunarscope.cybermoon.nl` (scheme, host and port only) |
| `-h`, `--help` | | Prints the usage and exits with code 1 |

`lunarscope-master hash-password` is a separate command: it asks for a new
password twice (echo off with `stty`), refuses fewer than 12 characters, and
prints the hash for `--password-file`. Piped input is read once without
prompts.

### `app()` — the router

| Route | Handler | Who |
|-------|---------|-----|
| Route | Handler | Who |
|-------|---------|-----|
| `GET /` | `dashboard::dashboard` | browser, logged in |
| `GET /server/{agent_id}` | `server::server` | browser, logged in |
| `GET /agents`, `POST /agents` | `agents::agents`, `create_agent` | browser, logged in |
| `GET /agents/new` | `agents::new_agent` | browser, logged in |
| `POST /agents/{id}/scans/{scan}` | `agents::toggle_scan` | browser, logged in |
| `POST /agents/{id}/scan-time` | `agents::set_scan_time` | browser, logged in |
| `POST /agents/{id}/delete` | `agents::delete_agent` | browser, logged in |
| `GET /scans`, `POST /scans` | `scans::scans`, `save_scan` | browser, logged in |
| `GET /scans/new`, `GET /scans/{name}` | `scans::new_scan`, `edit_scan` | browser, logged in |
| `POST /scans/{name}/delete` | `scans::delete_scan` | browser, logged in |
| `GET /report` | `report::report` | browser, logged in |
| `GET /login`, `POST /login` | `login::show_login`, `login` | browser |
| `POST /logout` | `login::logout` | browser |
| `GET /lang/{en,nl}` | `i18n::switch` | browser |
| `GET /static/htmx.min.js`, `/static/app.js` | `static_files::htmx`, `app_js` | browser |
| `GET /install/{token}` | `install::install_script` | new server (one-time link) |
| `GET /downloads/lunarscope-agent` | `install::download_agent` | new server |
| `GET /api/agent-config` | `api::agent_config` | agents (API key) |
| `POST /api/scan-complete` | `api::scan_complete` | agents (API key) |
| `POST /api/scan-result` | `api::scan_result` | agents (API key) |
| `POST /api/register-agent` | `api::register_agent` | administrator (admin token) |

All dashboard routes get the `require_login` middleware with `route_layer`,
so it only runs for them and an unknown path still answers 404. Their forms
have a 64 KiB body limit (rule scan source), the API routes 64 KiB
(`MAX_BODY_BYTES`), the login form 4 KiB. A wrong method on a known path
(e.g. `GET /api/scan-result`) answers 405.

### `run`, `serve`, `shutdown_signal`, `main`

- `run()` does the startup shown in section 4 and returns
  `Result<(), String>`. `main()` prints an error as
  `lunarscope-master: <message>` and exits with code 1.
- `serve()` uses axum's **graceful shutdown**: on Ctrl-C or SIGTERM
  (`systemctl stop`) it stops accepting connections, finishes running
  requests, then the pool is closed.
- `serve()` takes the listener and the shutdown signal as arguments, so the
  tests can start a real server on a random port and stop it.

## 6. `src/auth.rs`

### API keys

- `generate_api_key()`: `lsk_` + 32 random bytes as hex (256 bits) from the
  operating system. The prefix makes a leaked key easy to spot for secret
  scanners such as gitleaks.
- `hash_api_key(key)`: lowercase hex SHA-256. The keys are long random
  values, so a fast hash without salt is enough (reasoning in step 25).
- `bearer_token(header)`: takes `<key>` out of `Bearer <key>`. The word
  `Bearer` is case-insensitive, and an empty key is refused.
- `authenticate(pool, header)`: hashes the key and looks it up in
  `agents.api_key_hash`. Returns the agent id, 401 if the key is missing or
  unknown, or 500 on a database error.

### Extractors

An axum *extractor* runs before the handler. If it fails, the handler never
runs.

- **`AuthenticatedAgent(agent_id)`**: calls `authenticate()` with the
  `Authorization` header. Used by `scan_result`, so the API key is checked
  **before the body is even read**.
- **`Admin`**: compares the hash of the bearer token with
  `admin_token_hash` using `constant_time_eq` (the time doesn't depend on
  how many characters match). Answers 403 if registration is disabled and
  401 for a wrong token. Used by `register_agent`.

### Admin token

`load_admin_token(path)` reads the file, trims whitespace, and requires at
least **64 characters** (`openssl rand -hex 32`). It warns if the file is
readable by every user, and returns only the hash.

An agent key isn't accepted as an admin token, and the admin token isn't
accepted as an agent key (tests in `api.rs`).

## 7. `src/error.rs`

`ApiError { status, message }` turns into a JSON answer:

```json
{"error": "invalid or missing API key"}
```

- `unauthorized()` uses **one** message for every authentication failure, so
  a caller can't tell a wrong key from an unknown agent. It also adds
  `WWW-Authenticate: Bearer`.
- `bad_request(msg)` gives 400 with a message that says what's wrong.
- `internal(err)` logs the database error and answers only
  `"internal server error"`, so internal details never reach the caller.

## 8. `src/db/`

### `mod.rs`

`init_db(path)` opens the database with:

| Setting | Why |
|---------|-----|
| `create_if_missing(true)` | First start creates the file |
| WAL journal mode | The dashboard can read while agents write |
| `synchronous = NORMAL` | Faster. Safe with WAL: a power cut can lose the last commits but not corrupt the file |
| `foreign_keys = ON` | `REFERENCES … ON DELETE CASCADE` actually works |
| busy timeout 5 s | A query waits for a lock instead of failing at once |
| max 5 connections | Plenty for this load |

Then `run_migrations()` applies the migrations in `migrations/`, which are
embedded with `sqlx::migrate!()`. Migrations that already ran are skipped,
so this runs at every startup. `DbError` separates "could not open" from
"could not migrate".

### `queries.rs`

All SQL is in this file, and every value goes in through `?` parameters,
never into the SQL text (no SQL injection; test
`sql_in_fields_is_stored_as_plain_text`).

| Function | What it does |
|----------|--------------|
| `agent_id_by_key_hash` | Authentication lookup |
| `insert_scan_result` | **One transaction:** add to `scan_results`; upsert into `latest_results`, but only if it isn't older than what is there (`WHERE excluded.timestamp >= latest_results.timestamp`), moving `previous_severity`/`since` only when the severity changes; set the agent's `hostname` and `last_seen` |
| `insert_agent` | Registration (the trigger switches on the built-in scans) |
| `agent_overviews` | Every agent with the count per severity over its visible latest results. `LEFT JOIN`, so agents without results are listed too |
| `agent_by_id`, `agents` | One agent / all agents (without the key hash), with scan time, config version, check-in |
| `findings` | Newest result of every visible check with its hostname, optionally for one agent and/or one severity; Critical first, then hostname, module, check name. `latest_findings` = for one agent |
| `changes` | "Since previous scan": checks whose severity changed with their newest result (`since = timestamp`), in the agent's last round (within 6 h of `last_seen`): to Pass = resolved, from Pass or first result to a problem = new |
| `agent_config` | For `GET /api/agent-config`: version, scan time, enabled scans (built-in first) and the JSON of enabled rule scans; records the check-in |
| `scans`, `scan_by_name`, `enabled_scans` | Scans with how many agents use them; scans on for one agent |
| `save_rule_scan`, `delete_rule_scan` | Add/replace or delete a rule scan (never a built-in one) and raise the config version of the agents that have it on |
| `set_agent_scan`, `set_scan_time` | Switch a scan / set the time; raise the agent's config version only if something changed |
| `delete_agent` | With its results, scans and install links (cascade) |
| `create_agent` | "Add agent", one transaction: the agent with a placeholder key hash, exactly the picked scans, an install token |
| `use_install_token` | One transaction: drop expired tokens, delete this token, give the agent the new key hash |
| `remove_missing_checks` | After `POST /api/scan-complete`: per listed scan type, delete the agent's latest results whose check isn't in the list (JSON list via `json_each`); history stays |

The queries that need the `VISIBLE` or severity-order fragments are built
with `format!` from those constants only and passed as `AssertSqlSafe`;
values still go in as `?` parameters.

## 9. `src/routes/api.rs`

### `POST /api/scan-result`

The body is what the agent's `sender.rs` sends:

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

Checks, in this order:

| Check | Answer if it fails |
|-------|--------------------|
| Body ≤ 64 KiB | 413 |
| Valid API key (extractor) | 401 |
| Valid JSON, all fields, a known `severity` | 400 |
| `agent_id` in the body is the agent the key belongs to | 401 |
| Text fields not empty and not too long: `hostname` ≤ 255, `scan_type`/`check_name` ≤ 128, `description`/`remediation` ≤ 4096 characters | 400 |
| `timestamp` within **±60 s** of the server clock (`MAX_CLOCK_SKEW_SECONDS`, replay protection) | 400 |

If everything passes, the finding is stored and the answer is `200`.
`remediation` may be missing or `null`. Unknown extra fields are ignored,
so a newer agent can add fields without breaking an older master.

### `POST /api/register-agent`

```bash
curl -X POST https://lunarscope.cybermoon.nl/api/register-agent \
  -H "Authorization: Bearer $(cat /etc/lunarscope/admin-token)" \
  -H "Content-Type: application/json" \
  -d '{"hostname": "web-01"}'
```

Answer `201`:

```json
{"agent_id": "…uuid…", "hostname": "web-01", "api_key": "lsk_…"}
```

- Needs the admin token (`Admin` extractor): 401 for a wrong token, 403 if
  the master runs without `--admin-token-file`.
- The hostname is trimmed and checked like above.
- The `api_key` is shown **only in this answer**. The master stores just its
  hash, so a lost key means registering the agent again.
- The `agent_id` and `api_key` go into the agent's `config.toml`.

Since v0.3.0 the usual way is **Agents → Add agent** with its install link;
this endpoint stays for scripts.

### `GET /api/agent-config`

The agent's configuration, for the API key's agent (agent `remote.rs`):

```json
{"version": 4, "scan_time": "02:00",
 "modules": ["ssh_scan", "firewall_scan", "baseline_scan"],
 "rule_scans": [{"name": "baseline_scan", "description": "…", "checks": [ … ]}]}
```

Agents ask at startup and every 5 minutes; a different `version` makes them
scan right away with the new configuration. The request time is stored as
"last check-in".

### `POST /api/scan-complete`

Sent by the agent after a scan whose findings all reached the master: per
finished module the checks it reported. The master removes that agent's
latest results of those scan types whose check wasn't reported, so a
problem that a module only reports while it exists (e.g.
`ssh_config_readable`) disappears once it's fixed. Scan types that aren't
listed (a crashed module) keep their results. Answer `{"removed": n}`.
See [fix-0.3.0-stale-findings.md](fix-0.3.0-stale-findings.md).

## 10. `src/routes/dashboard.rs` — `GET /`

- Header: newest result of any agent and a dot: green, orange when an agent
  is stale, grey before the first result.
- Six tiles: servers and the totals per severity over the visible latest
  results.
- **Since previous scan**: `queries::changes` as Resolved / New lists.
- **Findings**: `queries::findings`, filtered with `?severity=` (only the
  five known values; anything else = all) and `?server=` (agent id). The
  filter form uses HTMX (`hx-get` on change, URL pushed); without
  JavaScript an Apply button appears. The 30 s refresh uses
  `refresh_url`, which keeps the filters (`url_with_query` percent-encodes
  them).
- `summaries()` turns `agent_overviews` into `AgentSummary` rows (worst
  severity, last seen or "never" in the page's language, stale), sorted
  worst first; used for the server filter and the Agents page.

### Stale agents

```rust
pub const STALE_AFTER_SECONDS: i64 = 25 * 3600;
pub fn is_stale(last_seen: Option<i64>, now: i64) -> bool
```

An agent is stale (last-seen time shown in red) when it hasn't reported for
more than **25 hours**: one missed daily scan plus an hour of margin. It was
2 hours before agent v0.2.0 switched to daily scans. An agent that never
reported isn't stale; it shows "never". `is_stale` is also used by the
detail page.

## 11. `src/routes/server.rs` — `GET /server/{agent_id}`

- Unknown agent: a **404** page in the dashboard layout (`not_found.html`).
- Otherwise: a header (id, registered, last seen with stale, scan time),
  five tiles, and the shared findings table for this agent.
- A database error gives a plain 500.

## 12. Agent management: `agents.rs`, `install.rs`, `scans.rs`, `report.rs`, `rule_scans.rs`, `i18n.rs`

### `routes/agents.rs`

- `GET /agents`: a card per agent: status badge (`CRITICAL` for a Critical
  result, `WARNING` for High/Medium, `OK`, `NEW` without results), counts
  with a distribution bar, last seen (orange when stale), last check-in, a
  **switch per scan** (a small form posting `enabled=1/0`; no JavaScript
  needed), the scan time field, Delete (with confirmation) and "View
  findings" (`/?server=<id>`).
- `POST /agents/{id}/scans/{scan}` and `/scan-time`: change and go back to
  the card (`/agents#agent-<id>`); unknown agent or scan → 404, a bad time
  → 400.
- `GET /agents/new`, `POST /agents`: hostname (letters, digits, `-`, `.`),
  scan time and a checkbox per scan (built-in on by default). Unknown scan
  names from a tampered form are dropped. Creates the agent and an install
  token (64 hex, 1 hour, only its SHA-256 stored) and shows the command
  `curl -fsSL <master>/install/<token> | sudo bash` once, with a warning if
  the master has no agent binary.

### `routes/install.rs`

- `GET /install/{token}` (no login; the token is the secret): in one
  transaction the link is deleted and the agent gets a **new API key**
  (only its hash is stored). The answer is a bash script with that key:
  installs `ca-certificates` if missing, creates the `lunarscope` user,
  downloads the binary, **checks its SHA-256**, writes
  `/etc/lunarscope/config.toml` (640, `root:lunarscope`) and the systemd unit,
  then `systemctl enable --now` (or prints how to start it without systemd).
  Unknown/used/expired link → 404 with a script that only prints why;
  no `--agent-binary` → 503 and the link stays valid.
- `master_url()`: `--public-url`, otherwise the Host header (https; http for
  localhost). Every value put into the script is checked or made by the
  master, so nothing can break out of its quotes.
- `GET /downloads/lunarscope-agent`: the binary (not secret).

### `routes/scans.rs` and `rule_scans.rs`

- `GET /scans`: built-in and rule scans, number of checks and agents.
- `GET /scans/new` (editor with `rule_scans::EXAMPLE`), `GET /scans/{name}`
  (rule scans only; built-in or unknown → 404).
- `POST /scans`: `rule_scans::parse` → error: the editor again with the
  text and the reason (400); OK: saved (replacing a rule scan with the same
  name; a built-in name is refused) and every agent that has it on gets a
  new config version.
- `rule_scans.rs` has the same six test types as the agent's `rules.rs`
  (`deny_unknown_fields`, no command type) and checks names (`[a-z0-9_]`,
  not a built-in name), 1–100 checks, unique check names, texts, absolute
  paths without `..`, octal modes, service/package names.

### `routes/report.rs`

Risk score over all visible latest results: `100 − 20·Critical − 8·High −
3·Medium − Low`, at least 0 (`SeverityCounts::risk_score`); `ok` ≥ 80,
`warn` ≥ 50, `crit` below. A gauge (SVG `stroke-dasharray`), the same score
per server (worst first) and the Critical and High findings with their
remediation. The period shown is the last 7 days.

### `i18n.rs`

One table of `(key, English, Dutch)` texts, so both languages always have
the same keys (tested). `Lang::from_headers` reads the `lunarscope_lang`
cookie (English by default); `GET /lang/{en,nl}` sets it for a year and
goes back to the page in the Referer, using only its path (no redirect to
another site). Templates use `t.<key>`, or `t | get(key="sev_" ~ severity)`
for a key made at render time. Finding texts from agents are not
translated.

## 13. Login: `src/session.rs` and `src/routes/login.rs`

Only the dashboard pages need a login. The API keeps its own keys, and
`/static/htmx.min.js` and `/login` are open.

### `session.rs`

| Item | What it does |
|------|--------------|
| `hash_password` | ≥ 12 characters, Argon2id with default parameters (19 MiB, 2 iterations), random salt → `$argon2id$v=19$m=19456,t=2,p=1$…` |
| `verify_password` | Argon2 check; a malformed hash never matches |
| `load_password_hash` | Reads `--password-file`, refuses anything that isn't an Argon2 hash (e.g. a plain password), warns if world-readable |
| `Login` | Password hash + `Sessions` + `LoginLimiter`. `check_password()` runs one Argon2 check at a time (each uses 19 MiB) |
| `Sessions` | In memory: SHA-256 of the token → expiry. A session lasts 12 h (`SESSION_LIFETIME`) from login; the HTMX refresh doesn't extend it. A restart logs everyone out |
| `LoginLimiter` | 5 wrong passwords within 60 s (`MAX_FAILED_LOGINS`, `FAILED_LOGIN_WINDOW`) → all logins refused until the oldest is a minute old. Counted for all clients together, because behind the proxy they all come from 127.0.0.1 |

### `routes/login.rs`

| Item | What it does |
|------|--------------|
| `require_login` | Middleware in front of every dashboard page: valid cookie → page; otherwise 303 to `/login`, or for an HTMX refresh 401 + `HX-Redirect: /login` (htmx then loads the login page instead of putting it in the table). No `--password-file` → 403 page |
| `show_login` | `GET /login`: the form, `Cache-Control: no-store` |
| `login` | `POST /login`: locked → 429; Argon2 check in `spawn_blocking`; wrong → 401 + counted; right → new session, cookie, 303 to `/` |
| `logout` | `POST /logout`: removes the session, clears the cookie, 303 to `/login` |
| `session_token` | Finds the `lunarscope_session` cookie (exact name) among the request's cookies |
| `logged_in_app` (tests only) | The app with a login and a valid cookie on every request; used by the dashboard and server page tests |

The cookie is
`lunarscope_session=<64 hex>; Path=/; Max-Age=43200; HttpOnly; Secure; SameSite=Strict`:
JavaScript can't read it, it only travels over https (browsers allow
`http://localhost` for testing), and other sites can't make the browser
send it, which also protects `POST /logout` from cross-site requests.

## 14. `src/templates.rs` and `templates/`

- The twelve templates are compiled into the binary (`include_str!`), so no
  templates directory is needed at runtime.
- `load()` parses them once at startup.
- Every render gets the view plus `t` (texts of the page's language),
  `lang` and `nav` (active sidebar item) through `Ui`.
- `render_page()` renders the whole page, or **only the `findings` block**
  when the request has `HX-Request: true`. It always sets
  `Cache-Control: no-store` (never show old security data) and
  `Vary: HX-Request`.
- `page()` renders other pages with a status code; all pages get
  `Cache-Control: no-store`. A rendering error is logged and answered with
  a plain 500, never with half a page.
- Shared types: `SeverityCounts` (with `add`, `total`, `risk_score`),
  `FindingRow`, `NotFoundView`; each route module has its own view structs.

| Template | Content |
|----------|---------|
| `base.html` | The reference design: all CSS (dark theme, tiles, badges, cards, drawer, forms; system fonts, nothing from other hosts), sidebar (Dashboard, Agents, Scans, Report, Log out, EN/NL), the details panel, loads htmx and `app.js`. Narrow screens: sidebar on top |
| `findings_table.html` | Part: the findings table; each row carries its details in `data-*` attributes |
| `dashboard.html` | Tiles, since previous scan, filters, findings |
| `server.html` | One agent: header, tiles, findings |
| `agents.html`, `agent_new.html`, `agent_install.html` | Agent cards; Add agent form; install command |
| `scans.html`, `scan_edit.html` | Scan list; TOML editor with the test types |
| `report.html` | Gauge, per-server table, actions |
| `not_found.html`, `login.html` | 404 message; login form (own layout without sidebar) |

`static/app.js` opens the details panel when a row is clicked (or Enter),
closes it with Escape or the overlay, asks for confirmation on forms with
`data-confirm`, and copies the install command. It only sets
`textContent`, so finding texts can't inject HTML.

### HTMX refresh

The `<section id="findings">` on the dashboard and server page has:

```html
hx-get="/?severity=High" hx-trigger="every 30s" hx-swap="outerHTML"
```

Every 30 s the browser fetches the same URL with `HX-Request: true`, gets
only the new section, and swaps it in. Because the new section has the same
attributes, it keeps polling. Without JavaScript the pages still work; they
just don't refresh.

## 15. `src/routes/static_files.rs`, `src/models.rs`, `src/time.rs`

- **`static_files.rs`**: serves the embedded htmx 2.0.11 (0BSD licence in
  `static/htmx.LICENSE`, checked against npm's SHA-512 in step 31) as
  `text/javascript`, cached by browsers for one day, and `app.js`
  (`no-cache`, it changes with the templates).
- **`models.rs`**: `Severity` with the same five names as the modules crate.
  `as_str()` gives the value stored in the database.
- **`time.rs`**: `unix_now()`, `format_utc()` (e.g. `2026-11-04 10:12
  UTC`) and `format_date()`. The date calculation (`civil_from_days`) is written out, so no date
  crate is needed.

## 16. Tests

`cargo test --locked` runs **221** tests. They all use an in-memory or
temporary SQLite database, so no setup is needed.

| File | Tests | Highlights |
|------|------:|------------|
| `main.rs` | 11 | Arguments (db path, listen address, admin token file, password file, agent binary, public URL), handlers can use the pool, every route is in `app()` (logged in), unknown path → 404, a real server on a socket (login page served, dashboard redirects) that shuts down gracefully |
| `auth.rs` | 15 | `authenticate` (valid, missing/malformed/unknown key, database error → 500), the extractor (handler gets the id, 401 without running the handler, non-UTF-8 header), SHA-256 hashing, `Bearer` parsing, key format and uniqueness, constant-time compare, admin token file (trimmed, too short, missing) |
| `db/mod.rs` | 32 | Built-in scans known, new agent gets them, scan kind and unknown scans refused, rule scan delete cascades, migration 3 keeps old agents and results, agent delete removes scans and links; `init_db` (creates the file, keeps data across restarts, connection options, foreign keys on every connection, refuses a changed migration or a non-SQLite file), table columns, constraints (`UNIQUE`, `NOT NULL`, `CHECK` on severity, `STRICT` types, foreign keys), cascade delete, index use, migration 2 back-fills `latest_results` |
| `routes/api.rs` | 41 | Scan complete (removes only unreported checks of listed scan types, own agent only, key and body checks, names as data); agent config (built-in defaults, check-in, API key, rule scans with definitions, only the agent's own scans, version bumps, built-in names protected); every answer code of both other endpoints, agent can only report as itself, clock skew, size limits, SQL text stored as plain text, key checked before the body, registration end to end, wrong HTTP method → 405 |
| `routes/dashboard.rs` | 24 | (Run logged in.) Filters, tiles, since previous scan, `since` only moves on a change, switched-off scans hidden and back, URL encoding; empty dashboard, only the newest result per check counts (also when an older one arrives late), modules and agents don't mix, agents without results listed, sorting, stale rule (including the daily-scan case), database failure → 500, HTMX polling and fragment, `no-store` + `Vary` headers |
| `session.rs` | 12 | Argon2 hash format and check, random salt, minimum length, malformed hashes, password file (trimmed, plain password refused, missing), sessions (64 hex, expiry after 12 h, unknown/removed, stored hashed, expired ones dropped), lockout after 5 in a minute |
| `routes/login.rs` | 12 | Redirect without a session (also HTMX: `HX-Redirect`), locked without `--password-file`, the form, right password → cookie with all flags opens the dashboard, wrong passwords, forged cookies, exact cookie name, lockout → 429, logout, API and htmx need no login, sessions per instance |
| `routes/server.rs` | 15 | (Run logged in.) 404 page, page without results, sort order, newest result per check only, no other agents' findings, details shown, stale marking, HTML escaping (also in `hx-get`), path tricks don't reach other pages, database failure → 500, HTMX polling and fragment |
| `templates.rs` | 15 | All templates parse and are embedded; every page renders in EN and NL as a full document without template syntax and loads nothing from other hosts; sidebar marks the page; dashboard content; agents, install and report pages; HTML escaping (also in `data-*`); `HX-Request` detection; the `findings` block alone; unknown template → 500 |
| `routes/agents.rs` | 12 | Cards, switches raise the version only on a change, unknown agent/scan 404, scan time, delete, the form, bad input, **install flow end to end** (one-time, new key, SHA-256 in the script), expired links, no login needed for install/download but for pages, no binary → 503 and link kept |
| `routes/install.rs` | 5 | Master URL from option or Host (unsafe Host refused), public URL check, script passes `bash -n`, script checks the download, ELF check |
| `routes/scans.rs` | 5 | List, example in the editor, save/edit/delete, invalid scan comes back with the reason, no editor for built-in/unknown |
| `routes/report.rs` | 3 | Score formula, classes, the page (scores, order, actions) |
| `rule_scans.rs` | 7 | Example valid, JSON for the agent, every test type, no command type, bad values with reasons, names and checks, TOML errors |
| `i18n.rs` | 4 | Keys unique and translated, cookie, Referer paths only local, the switch |
| `static_files.rs` | 3 | The embedded file is htmx 2.0.11, served as JavaScript, other static paths → 404 |
| `models.rs`, `time.rs` | 2 + 3 | Severity names match `lunarscope-modules` and other spellings are refused; known dates (including 29 February), every day follows the previous one, `unix_now` is plausible |

Other checks used for releases:

```bash
cargo clippy --all-targets --all-features --locked -- -D warnings
cargo fmt --check
```

`templates::tests::every_file_in_templates_dir_is_embedded` reads the
`templates/` folder from the source path, so it fails when the test binary
runs somewhere the source isn't (see the re-test of 2026-11-04). In a
normal `cargo test` it passes.

## 17. `lunarscope-master.service`

- Runs as user `lunarscope`:
  `lunarscope-master --db /var/lib/lunarscope/master.db --listen 127.0.0.1:3000 --admin-token-file /etc/lunarscope/admin-token --password-file /etc/lunarscope/dashboard-password`.
- `/etc/lunarscope/dashboard-password` (root:lunarscope, mode 640) holds the
  output of `lunarscope-master hash-password`.
- For install links, add `--agent-binary <path>` and `--public-url <url>` to
  `ExecStart` (not in the shipped unit, because the paths depend on the
  server).
- `StateDirectory=lunarscope` creates `/var/lib/lunarscope` and makes it the
  only writable path. SQLite also needs to create its `-wal`/`-shm` files
  there.
- `Restart=on-failure` after 5 s, at most 5 starts in 5 minutes.
- The same hardening as the agent: no capabilities, read-only system, system
  call filter, `MemoryDenyWriteExecute`, only `AF_INET`/`AF_INET6`/`AF_UNIX`.

## 18. Where to change things

| You want to… | Change |
|--------------|--------|
| Add a field to scan results | `ScanResultRequest` + `validate()` in `api.rs`, `NewScanResult` + `insert_scan_result` in `queries.rs`, a **new** migration file (never edit an applied one), the templates, **and** the agent's `Payload` |
| Add a page | A handler in `routes/`, a route in `app()` (`main.rs`), a template in `templates/` plus its line in `TEMPLATES` (`templates.rs`), a view struct |
| Change what the dashboard shows | `findings`/`changes`/`agent_overviews` (`queries.rs`), `dashboard()` and `DashboardView` (`dashboard.rs`), `dashboard.html` |
| Add or change a text | A row in `TEXTS` in `i18n.rs` (both languages), then `{{ t.<key> }}` in the template |
| Add a rule test type | `Test` + `validate_test` in `rule_scans.rs`, the help text in `i18n.rs`, **and** the agent's `rules.rs` (new agent release) |
| Know a new built-in module | A new migration adding its row to `scans` (and existing agents' `agent_scans` if it should be on) |
| Change install links | `INSTALL_LINK_SECONDS` and `script()` in `install.rs`; the agent unit in `install/lunarscope-agent.service` (keep in sync with the agent repo) |
| Change the stale limit | `STALE_AFTER_SECONDS` in `dashboard.rs` (keep it above the agents' scan interval) |
| Change the refresh time | `hx-trigger="every 30s"` in `dashboard.html` and `server.html` |
| Change the clock-skew limit or body size | `MAX_CLOCK_SKEW_SECONDS`, `MAX_BODY_BYTES` in `api.rs` |
| Change the look | The `<style>` block and `:root` colours in `base.html` |
| Change database settings | `init_db()` in `db/mod.rs` |
| Change the session length or lockout | `SESSION_LIFETIME`, `MAX_FAILED_LOGINS`, `FAILED_LOGIN_WINDOW` in `session.rs` (the cookie's `Max-Age` follows `SESSION_LIFETIME`) |
| Put a new page behind the login | Add its route to the `dashboard` router in `app()`, the one with `route_layer(require_login)`; give it a `nav` value in `Ui::new` if it belongs to a sidebar item |
| Change the dashboard password | Run `hash-password` again, replace the file, restart the master |

After any change: run the tests, clippy and fmt, bump the version in
`Cargo.toml`, and add a change file in this folder.

## 19. New in 0.4.0

Sections 1–18 describe 0.3.0. What 0.4.0 adds, with the why in the change
files:

| Change file | What |
|-------------|------|
| [change-0.4.0-scan-now-install-link-health.md](change-0.4.0-scan-now-install-link-health.md) | Scan now / Scan all, new install link, `/healthz`, `form_id` against double agents |
| [change-0.4.0-history-cleanup-backups.md](change-0.4.0-history-cleanup-backups.md) | `maintenance.rs`, `--keep-days`, `--backups`, `--backup-dir` |
| [change-0.4.0-time-zone-settings.md](change-0.4.0-time-zone-settings.md) | Settings page, `settings.rs`, zone-aware times, scan times converted to UTC |
| [change-0.4.0-user-accounts.md](change-0.4.0-user-accounts.md) | Users, admin/read-only roles, audit log |
| [change-0.4.0-agent-self-update.md](change-0.4.0-agent-self-update.md) | Signed agent updates, Agent updates tab |
| [change-0.4.0-https-caddy.md](change-0.4.0-https-caddy.md) | `install/Caddyfile` |
| [change-0.4.0-ci-and-dependencies.md](change-0.4.0-ci-and-dependencies.md) | CI, `deny.toml`, security updates |

### New files

| File | What it does |
|------|--------------|
| `migrations/0004_users_settings_updates.sql` | `agents.form_nonce`, `agent_version`, `update_requested`; tables `settings`, `users`, `audit_log` |
| `src/audit.rs` | `log(state, action, detail)` with the logged-in user |
| `src/maintenance.rs` | Daily cleanup, `VACUUM INTO` backup, rotation |
| `src/settings.rs` | The time zone setting (`AppState.settings`, a `RwLock`) |
| `src/updates.rs` | `UpdateOffer`, version compare, `.sig` loading, version from User-Agent |
| `src/db/users.rs` | Users and audit log queries |
| `src/routes/settings.rs` | `GET/POST /settings` |
| `src/routes/users.rs` | `/settings/users…`, `/settings/audit` |
| `src/routes/updates.rs` | `/settings/updates…` |
| `templates/settings.html`, `settings_tabs.html`, `users.html`, `audit.html`, `updates.html` | Settings pages |
| `install/Caddyfile` | HTTPS in front of the master |
| `deny.toml` | cargo-deny rules |

### Changed in existing parts

- **`AppState`:** `login: Arc<session::Login>` (always present),
  `settings: Arc<RwLock<Settings>>`; `AgentBinary.offer`.
- **Arguments:** `--keep-days`, `--backups`, `--backup-dir`; subcommand
  `add-user <name> [--viewer] [--db <path>]`. `--password-file` now only
  creates user `admin` while there are no users.
- **Login (`session.rs`, `routes/login.rs`):** sessions hold a `User`;
  `require_login` runs the handler inside `CURRENT_USER.scope(…)` and lets
  read-only users through only for `viewer_may` (GET, not `/settings…`,
  `/agents/new`, `/scans/…`).
- **`Ui`:** carries the language, time zone and user; `ui.time()`,
  `ui.date()`; templates get `is_admin`, `current_user`, `current_role`,
  `tz_name`.
- **`GET /api/agent-config`:** records the agent's version (User-Agent),
  sends `scan_time` as the UTC time of the next local scan, and `update`
  when requested and newer.

### New routes

| Route | Who |
|-------|-----|
| `GET /healthz` | anyone |
| `POST /agents/scan-all`, `/agents/{id}/scan-now`, `/agents/{id}/install-link` | admin |
| `GET/POST /settings` | admin |
| `GET/POST /settings/users`, `POST /settings/users/{id}/delete`, `/settings/users/{id}/password` | admin |
| `GET /settings/audit` | admin |
| `GET /settings/updates`, `POST /settings/updates/all`, `/settings/updates/{agent_id}` | admin |

### Where to change things (additions)

| You want to… | Change |
|--------------|--------|
| Let read-only users see or do more | `viewer_may` in `routes/login.rs` (and the `{% if is_admin %}` blocks) |
| Audit a new action | `audit::log(&state, "<action>", &detail)` in the handler |
| Change cleanup or backup defaults | `Args` defaults in `main.rs`, `maintenance.rs` |
| Add a setting | A row in `settings`, a field in `Settings` (`settings.rs`), the form in `settings.html` |

## 20. New in 0.5.0

Details in [change-0.5.0-ui-feedback.md](change-0.5.0-ui-feedback.md).

| Part | What |
|------|------|
| `migrations/0005_scan_moments.sql` | `agents.last_scan_at`, `previous_scan_at`; setting `time_format` |
| `queries::record_scan` | Called by `POST /api/scan-complete`: last scan → previous, now → last |
| `GET /agents/{id}/scans` (`agents::edit_scans`, `agent_scans.html`) | Change scans for one server; explanation from `explain_<scan>` texts for built-in scans; `data-confirm` per switch |
| Dashboard filters | `Filters {severity, server, scan, q, hide_pass}`; severity and server in SQL, the rest in `dashboard::matches` |
| `Settings.hour12`, `Ui::time`, `Ui::clock` | 24h or AM/PM everywhere |
| `i18n::Lang` | Default `Nl` |
| `static/app.js` | `showFinding` (jump + flash), unsaved scan time note, leave warning |
| Tests | `routes::login::english(router)` adds the English language cookie, so tests can check English texts |

| You want to… | Change |
|--------------|--------|
| Explain another built-in scan | Add `explain_<scan name>` to `TEXTS` in `i18n.rs` |
| Add a dashboard filter | `Filters`, `matches()` (or the SQL in `queries::findings`), `refresh_url`, the form in `dashboard.html` |

