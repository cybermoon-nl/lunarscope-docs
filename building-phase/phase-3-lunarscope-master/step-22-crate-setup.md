# Step 22 — Repo + binary crate

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

Turn the `lunarscope-master` repo into a binary crate with axum, tokio, sqlx
(SQLite + runtime), tera, serde, serde_json and tower-http (for static files).

## What was done

As in steps 1 and 11, the repo already existed (README + `.github/`), so the
crate was initialised in place:

```bash
cd repos/lunarscope-master
cargo init --bin --name lunarscope-master
cargo add axum
cargo add sqlx --no-default-features --features runtime-tokio,sqlite,macros,migrate
cargo add tera
cargo add tower-http --features fs
cargo add tokio --features rt-multi-thread,macros,net,signal
cargo add serde --features derive
cargo add serde_json
```

`src/main.rs` only contains a doc comment and an empty `main()` for now; the
server is built up in steps 23–32.

### `Cargo.toml` (dependencies)

```toml
[dependencies]
axum = "0.8.9"
serde = { version = "1.0.229", features = ["derive"] }
serde_json = "1.0.154"
sqlx = { version = "0.9.0", default-features = false, features = ["macros", "migrate", "runtime-tokio", "sqlite"] }
tera = "2.4.0"
tokio = { version = "1.54.1", features = ["rt-multi-thread", "macros", "net", "signal"] }
tower-http = { version = "0.7.1", features = ["fs"] }
```

## Choices and justification

### sqlx

- **`default-features = false`** — sqlx's defaults include the `any` driver
  (runtime choice of database) and `json`. Only SQLite is needed. The
  dependency tree confirms that no MySQL/PostgreSQL driver and no TLS library
  is compiled in (`sqlx-core`, `sqlx-macros`, `sqlx-sqlite` only).
- **`sqlite`** — in sqlx 0.9 this means **`sqlite-bundled`**: SQLite
  **3.51.3** is compiled into the binary (`libsqlite3-sys` 0.37). The master
  doesn't depend on the SQLite version installed on the VPS, and stays a
  single binary, as the architecture document intends.
- **`runtime-tokio`** — the same async runtime as axum.
- **`migrate`** — for running the `CREATE TABLE` migrations at startup
  (step 23, `sqlx::migrate!()`).
- **`macros`** — for `sqlx::query!` / `query_as!`, the "compile-time verified
  queries" from the architecture document (3.2.4). These macros check SQL
  against a real database schema while compiling. That needs either a
  `DATABASE_URL` during the build, or a committed `.sqlx/` query cache
  (`cargo sqlx prepare`) so CI can build offline. How to set that up is
  decided in step 25, when the first real queries are written (moved from
  step 23, see there).

### axum (0.8, default features)

The defaults give HTTP/1 (`http1`), JSON (`Json` for the API, step 25), forms
(`Form`, possibly for the dashboard), query strings and the tokio
integration. HTTP/2 and WebSockets are not needed: agents send short POSTs
(architecture document 5.1 rejected WebSockets).

### tokio

- **`rt-multi-thread`** — unlike the agent (which does one thing at a time,
  step 17), the master serves many agents and dashboard users at the same
  time, so it uses all CPU cores.
- **`net`** — `TcpListener` for binding `0.0.0.0:3000` (step 32).
- **`signal`** — graceful shutdown on `SIGTERM` (`systemctl stop`), so running
  requests and SQLite writes finish cleanly.
- **`macros`** — `#[tokio::main]` and `#[tokio::test]`.

### tera (2.x)

Tera 2 is the current major version. Its API differs from Tera 1, which most
online examples use, so the step 28 templates follow the 2.x API. No optional
features are enabled. The `glob_fs` feature (loading templates from a
directory with a glob) was left out on purpose. In step 28 the templates can
be embedded in the binary with `include_str!` + `add_raw_template`, which
keeps the master a single file and avoids a templates path in the systemd
sandbox. The final choice is made in step 28.

### tower-http with `fs`

`ServeDir` for static files: the HTMX script (step 28) and CSS. Serving HTMX
from the master itself instead of a CDN means the dashboard has no
third-party requests (privacy, works without internet access).

## Checks

| Check | Result |
|-------|--------|
| `cargo build` (first build) | ✅ 14 s, 172 crates |
| `cargo clippy --all-targets --locked -- -D warnings` | ✅ no warnings |
| `cargo fmt --check` | ✅ |
| Database drivers in the tree | only `sqlx-sqlite` + `libsqlite3-sys` 0.37 (SQLite 3.51.3, bundled) ✅ |
| TLS libraries in the tree | none ✅ (sqlx needs none for SQLite; how the master serves HTTPS — reverse proxy or TLS in the binary — is decided in step 32) |
| `.gitignore` | `/target` |

No tests yet: there is no code at this point. Tests start with the database
layer in step 23.

### Licences (for `deny.toml`, step 37)

`cargo tree --format {l}` for the master contains, besides MIT/Apache-2.0:
`Unicode-3.0`, `BSD-3-Clause` (with MIT), `Zlib`, `BSL-1.0` (as an
alternative to Apache-2.0) and `Unlicense OR MIT`. As with the agent
(step 21), the allow-list in step 37 needs more than MIT/Apache-2.0/ISC.

## Later changes

- **Step 31** removed `tower-http`: the only static file (htmx) is embedded
  in the binary instead of served from a directory.

## Next step

Step 23 — database setup (migrations for `agents` and `scan_results`).
