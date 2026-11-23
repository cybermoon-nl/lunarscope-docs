# Change (0.4.1) — login lockout per address

**Repo:** `lunarscope-master` 0.4.1
**Date:** 2026-11-17
**Status:** Done — code, tests, mutation checks, tested over HTTP; not
committed yet

## Why

Since 0.2.0, 5 wrong passwords within a minute locked the login for
**everyone**. On the dev laptop that was fine. On a public server (the
demo, see [demo-version.md](demo-version.md)) any stranger could keep the
login blocked by guessing all the time, so the admin could never log in.

## What it does now

| Limit | Effect |
|-------|--------|
| 5 wrong passwords per client address within 60 s | That address gets `429` "Wait a minute"; other addresses can still log in |
| 100 wrong passwords over all addresses within 60 s | Everyone waits (backstop against guessing from many addresses) |

**The client address:** the TCP peer of the connection. Only when that is
the machine itself (`127.0.0.1`/`::1`, a reverse proxy like Caddy on the
same server) is the **last** entry of `X-Forwarded-For` used, the one the
proxy added. So someone connecting directly can't choose an address with
that header, and earlier entries a client puts in the header itself are
ignored. Without either (tests) the address is "unknown", one shared
bucket.

Old entries are dropped on every check, so the table only holds addresses
with a failure in the last minute (at most ~100 because of the backstop).

## Code

| File | Change |
|------|--------|
| `src/session.rs` | `LoginLimiter` keeps failures per `Option<IpAddr>`; `is_locked(client, now)`, `record_failure(client, now)`; `MAX_FAILED_LOGINS_TOTAL` = 100 |
| `src/routes/login.rs` | `client_address(peer, headers)`; `login` takes the peer via `Extension<ConnectInfo<SocketAddr>>` (optional) |
| `src/main.rs` | `into_make_service_with_connect_info::<SocketAddr>()` |
| `Cargo.toml` | 0.4.1 |

## Tests

Master **273** (+3).

| Test | Checks |
|------|--------|
| `limiter_locks_an_address_after_five_failures_within_a_minute` | Locked after 5; another address and "unknown" not; free again after 60 s |
| `many_addresses_together_lock_everyone` | 25 addresses × 4 failures: none locked alone, but the total locks a new address; old addresses forgotten |
| `a_locked_address_does_not_lock_out_others` | Over HTTP: 5 × 401 from one address, then 429 with the right password; the right password from another address → 303 |
| `client_address_trusts_forwarded_for_only_from_this_machine` | Last entry behind a local proxy; header ignored for a remote peer; garbage or no header → peer |
| `too_many_wrong_passwords_lock_the_login` (existing) | Still passes ("unknown" address) |

`cargo clippy --all-targets --all-features -- -D warnings` and
`cargo fmt --check`: clean.

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| One bucket for everyone again | 2 tests |
| No backstop | `many_addresses_together_lock_everyone` |
| `X-Forwarded-For` trusted from any peer | `client_address_trusts_forwarded_for_only_from_this_machine` |
| First (client-chosen) entry of the header used | same |

4 of 4 caught.

### Over real HTTP

The demo build (same code) on `127.0.0.1:3041`: 5 wrong passwords with
`X-Forwarded-For: 203.0.113.9` → `401 401 401 401 401`; the right password
from that address → `429`, from `198.51.100.7` → `303`.
