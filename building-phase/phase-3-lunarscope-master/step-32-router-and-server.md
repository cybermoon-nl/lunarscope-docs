# Step 32 — Combine the axum router and serve

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

Combine all routes in `main.rs` (`Router::new().route("/", get(dashboard))
.route("/api/scan-result", post(api_scan_result))…`) and bind to
`0.0.0.0:3000`.

## What was done

### The router

All routes were already added to `app()` as each step was built (steps
25–31), so each step could be tested through the real router. `app()` is the
single place where they come together:

```rust
/// | Route                       | Who            | Step |
/// |-----------------------------|----------------|------|
/// | `GET  /`                    | admin, browser | 29   |
/// | `GET  /server/{agent_id}`   | admin, browser | 30   |
/// | `GET  /static/htmx.min.js`  | browser        | 31   |
/// | `POST /api/scan-result`     | agents         | 25   |
/// | `POST /api/register-agent`  | admin (token)  | 27   |
fn app(state: AppState) -> Router {
    Router::new()
        .route("/", get(routes::dashboard::dashboard))
        .route("/server/{agent_id}", get(routes::server::server))
        .route("/static/htmx.min.js", get(routes::static_files::htmx))
        .route("/api/scan-result", post(routes::api::scan_result)
            .layer(DefaultBodyLimit::max(routes::api::MAX_BODY_BYTES)))
        .route("/api/register-agent", post(routes::api::register_agent)
            .layer(DefaultBodyLimit::max(routes::api::MAX_BODY_BYTES)))
        .with_state(state)
}
```

### Listening and shutting down

```rust
let listener = TcpListener::bind(args.listen).await
    .map_err(|err| format!("could not listen on {}: {err}", args.listen))?;
eprintln!("listening on http://{}", args.listen);

let db = state.db.clone();
serve(listener, state, shutdown_signal()).await?;   // until Ctrl-C / SIGTERM
db.close().await;
eprintln!("stopped");
```

- `serve()` wraps `axum::serve(listener, app(state)).with_graceful_shutdown(…)`.
  It takes the shutdown signal as a parameter, so a test can stop it.
- `shutdown_signal()` completes on **Ctrl-C or SIGTERM**. `systemctl stop`
  sends SIGTERM.

### New option

| Argument | Default |
|----------|---------|
| `--listen <address:port>` | `0.0.0.0:3000` |

Full usage: `lunarscope-master [--db <path>] [--listen <address:port>]
[--admin-token-file <path>]`.

## Choices and justification

### Graceful shutdown

Without it, `systemctl stop` or a restart for an update kills the process
mid-request. An agent's POST could be cut off after the database insert but
before the response, and the agent would log an error for a finding that was
actually stored. With graceful shutdown the master stops accepting new
connections, finishes the running requests, closes the pool (SQLite
checkpoints the WAL file), and exits **0**. systemd then sees a clean stop,
not a failure.

### `0.0.0.0:3000` as the default, configurable with `--listen`

The guide's address is the default, so a quick start for development and
the end-to-end test (step 33) needs no options. **In production the master
should be started with `--listen 127.0.0.1:3000` behind a reverse proxy**
(see below). Port 3000 is also not opened in the VPS firewall (architecture
6.2: only 443 and 22). The address is parsed as a `SocketAddr`, so a typo
(`localhost:3000`, port 99999) is refused at startup with a clear message,
not at bind time.

A bind failure ends the program with one line and exit code 1:
`could not listen on 127.0.0.1:3000: Address already in use (os error 98)`.
This happened for real on the development machine, where another program
already uses port 3000 (see the [run log](evidence/step-32-binary-run.txt)).

### HTTPS in production: a reverse proxy (decision deferred from step 22)

The architecture document (5.5, 6.4) requires **TLS 1.3** with a **Let's
Encrypt** certificate on port 443, renewed automatically. Two ways to do that
were considered:

| | TLS inside the master (rustls + certbot files) | Reverse proxy in front (e.g. Caddy) |
|---|---|---|
| Certificate renewal | certbot renews files; the master must reload them without restarting (extra code) | proxy gets and renews certificates itself (ACME built in) |
| TLS 1.3 only | configure rustls | one line in the proxy config |
| HTTP → HTTPS redirect, port 80 for ACME | extra listener in the master | built in |
| Slow/huge requests, timeouts | must be added to the master | handled by the proxy |
| Extra component | no | yes (one package on the VPS) |

**Chosen: a reverse proxy.** The master listens on `127.0.0.1:3000` only and
speaks plain HTTP on the loopback interface. The proxy terminates TLS 1.3 on
port 443. Certificate handling and exposure to the internet stay with
software built for exactly that, and the master keeps no TLS code or
dependencies. An example with Caddy:

```caddyfile
lunarscope.example.com {
    reverse_proxy 127.0.0.1:3000
    tls {
        protocols tls1.3
    }
}
```

Consequences that were already taken into account:

- **The agent** requires `https://` for every non-local master and enforces TLS
  1.3 itself (agent step 16), so it works unchanged with the proxy.
- **Agent registration** is protected by the admin token, *not* by "only from
  127.0.0.1" (step 27). Behind a proxy on the same host every request comes
  from 127.0.0.1, so an address check would have opened registration to the
  internet.
- Setting up the proxy and the systemd unit on the VPS is deployment work. It
  is not part of the guide's phase 3, and it is listed as an open point for
  deployment.

### Measured

| | Architecture document (2.2) | Measured (release build, dev machine) |
|---|---:|---:|
| Binary size | ~12 MB | **8.1 MB** (8,057,624 bytes, default release profile) |
| Memory while running | ~17 MB | **8.8 MB** RSS (`VmHWM` 8,816 kB) |
| Threads | — | 19 (tokio multi-threaded runtime: one worker per CPU core, plus helpers) |

The agent's size optimisations (step 19: `opt-level="s"`, LTO, strip) were
**not** applied to the master. It is installed once on a VPS, not on many
customer servers, so size matters much less there.

## Checks

### Unit tests (`src/main.rs`)

| Test | Checks |
|------|--------|
| `listen_address_default_and_argument` | Default `0.0.0.0:3000`; IPv4 and IPv6 addresses; `3000`, `localhost:3000`, missing port, port 99999 → clear error; missing value → error |
| `every_route_is_combined_in_app` | Each route answers with its own handler: `GET /` 200, `GET /server/unknown` 404 page, `GET /static/htmx.min.js` 200, `POST /api/scan-result` 401, `POST /api/register-agent` 403 (no token configured), wrong method 405, unknown path 404 |
| `serves_over_a_real_socket_and_shuts_down_gracefully` | `serve()` on a real TCP port (`127.0.0.1:0`): raw HTTP/1.1 requests get `200 OK` with the page and `401 Unauthorized` from the API; after the shutdown signal `serve()` returns `Ok` within 5 s and the port no longer accepts connections |

A fourth test ("binding a used port fails") was written and then removed. It
only tested the operating system, not Lunarscope code. The binary's
behaviour for a used port was checked by hand instead (below).

Total master tests: **132**, all passing.

### Mutation checks

| Bug introduced | Failing tests |
|----------------|---------------|
| htmx route left out of `app()` | `every_route_is_combined_in_app`, `htmx_is_served_as_javascript` |
| register route left out of `app()` | `every_route_is_combined_in_app` + all registration tests |
| shutdown signal ignored (`pending()`) | `serves_over_a_real_socket_and_shuts_down_gracefully` (server doesn't stop within 5 s) |

### Running the release binary

([full log](evidence/step-32-binary-run.txt))

| Action | Result |
|--------|--------|
| Start with `--listen 127.0.0.1:38132 --admin-token-file …` | "listening on http://127.0.0.1:38132" |
| `GET /`, `GET /static/htmx.min.js` | 200 HTML, 200 JavaScript (52,182 bytes) |
| `curl` register an agent with the admin token | **201**, UUID + `lsk_…` key (68 chars) |
| `curl` scan result with that key, fresh timestamp | **200**, appears on the dashboard with a High badge; detail page 200 |
| Same with a timestamp 120 s old | **400** with the reason |
| Wrong key | **401** |
| Second master on the same port | "Address already in use", exit 1 |
| `kill -TERM` | "shutting down", "stopped", **exit 0** |

```text
$ cargo test                                → 132 passed, 0 failed
$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

## Next step

Step 33 — end-to-end test: real master + real agent locally.
