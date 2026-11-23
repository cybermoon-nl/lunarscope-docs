# Change 0.2.0 — login for the dashboard

**Repo:** `lunarscope-master` (0.1.0 → **0.2.0**)
**Date:** 2026-11-16
**Status:** Done — code and checks ready; commit + tag by hand

Master 0.2.0 also contains the 25 h stale limit from
[change-0.2.0-daily-scan-time.md](../phase-2-lunarscope-agent/change-0.2.0-daily-scan-time.md).
That change was planned as master 0.1.1 but never released on its own, so
both go out together as 0.2.0.

## Why

Until now the dashboard (`GET /`) and the detail pages
(`GET /server/{agent_id}`) needed no login. Anyone who could open the URL
saw which servers allow root login over SSH, have no firewall, or miss
security updates. For an attacker that is a list of where to start. The API
(`/api/*`) was already protected by API keys and the admin token; the pages
were not. The Caddy example in step 32 passes everything through, so in
production the pages would have been public.

## Decisions

| Question | Choice | Reason |
|----------|--------|--------|
| Where | **In the master**, not in the reverse proxy | The protection is part of the tested code and works with any proxy |
| What you type | **A separate dashboard password** | Rejected: logging in with the admin token (one secret for curl and browser) |
| How it is stored | **Argon2id hash** in a file (`--password-file`), made with the new command `lunarscope-master hash-password` | A password chosen by a person can be guessed much more easily than a 256-bit key, so it needs a slow hash. Argon2id with the crate's default parameters (19 MiB, 2 iterations) is the current recommendation (OWASP). New crate: `argon2` 0.6 |
| Sessions | Random 256-bit token in a cookie, **in memory**, 12 h | No database change needed. A restart of the master logs everyone out, which is fine for one administrator |
| Without `--password-file` | Dashboard **locked** (403 with an explanation) | Safe by default: forgetting the option doesn't make the dashboard public. This changes the behaviour of an existing installation, so the version is 0.2.0 |
| Guessing | 5 wrong passwords within 60 s → all logins refused (429) until a minute has passed | Behind the proxy every request comes from 127.0.0.1, so a limit per IP address wouldn't help. Downside: someone guessing also locks the administrator out for at most a minute |

## What a user sees

1. Opening the dashboard without a session redirects to `/login`.
2. `/login` shows one password field.
3. Wrong password: "Wrong password." (401). Five wrong passwords in a
   minute: "Too many wrong passwords. Wait a minute and try again." (429).
4. Right password: redirect to the dashboard, which has a **Log out**
   button at the top right.
5. Log out, or 12 hours after logging in: back to `/login`. The HTMX refresh
   (every 30 s) doesn't extend the session. When the session ends while the
   dashboard is open, the next refresh gets `HX-Redirect: /login`, so htmx
   loads the login page instead of putting it inside the table.

## Code

### New: `src/session.rs`

| Item | What it does |
|------|--------------|
| `hash_password(password)` | Refuses passwords under 12 characters, returns the PHC string `$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>` with a random salt |
| `verify_password(password, hash)` | Argon2 check. A malformed hash never matches |
| `load_password_hash(path)` | Reads `--password-file`, refuses anything that isn't an Argon2 PHC string (so a plain password put there by mistake stops the start), warns if the file is world-readable |
| `Login` | The password hash, the sessions and the limiter. `check_password()` lets only one Argon2 check run at a time, so a burst of logins can't use a lot of memory |
| `Sessions` | Token → expiry time. Stores only the **SHA-256 of each token** (like the API keys), removes expired sessions when a new one is made |
| `LoginLimiter` | Times of recent wrong passwords; `is_locked()` when 5 are within 60 s |

### New: `src/routes/login.rs`

| Item | What it does |
|------|--------------|
| `require_login` (middleware) | In front of `/` and `/server/{agent_id}`. Valid session cookie → the page. No or invalid cookie → 303 to `/login`, or for an HTMX refresh 401 with `HX-Redirect: /login`. No `--password-file` → 403 page |
| `GET /login` | The form (`Cache-Control: no-store`) |
| `POST /login` | Checks the lock, then the password (in `spawn_blocking`, because Argon2 takes tens of milliseconds and would block the server). Right: new session, `Set-Cookie`, 303 to `/`. Logs "dashboard login" or "dashboard login failed: wrong password" |
| `POST /logout` | Removes the session, clears the cookie, 303 to `/login` |

The cookie:

```text
lunarscope_session=<64 hex>; Path=/; Max-Age=43200; HttpOnly; Secure; SameSite=Strict
```

- `HttpOnly`: JavaScript can't read it.
- `Secure`: only sent over https. Browsers make an exception for
  `http://localhost` / `127.0.0.1`, so local testing still works.
- `SameSite=Strict`: other websites can't make the browser send it. This
  also protects `POST /logout` against cross-site requests (CSRF). A
  cross-site `POST /login` would need the password.

### Changed

| File | Change |
|------|--------|
| `src/main.rs` | `AppState.login: Option<Arc<Login>>` and `AppState::with_login()`. Option `--password-file`. Subcommand `hash-password`. Router: the two dashboard routes get the middleware with `route_layer`, so an unknown path still gives 404. New routes `/login` (form body max 4 KiB) and `/logout`. Startup line ends with `dashboard login enabled` or `dashboard locked (no --password-file)` |
| `src/auth.rs` | `random_hex()` split out of `generate_api_key()`; used for API keys and session tokens |
| `templates/login.html` | New page |
| `templates/base.html` | `{% block nav %}` in the navigation bar, styles for the login form |
| `dashboard.html`, `server.html`, `not_found.html` | Log out button in that block |
| `src/templates.rs` | `login.html` added to the embedded templates |
| `Cargo.toml` | `argon2 = "0.6.0"`; `argon2` and `blake2` built with `opt-level = 3` in debug/test builds (otherwise one hash takes seconds in `cargo test`); version 0.2.0 |
| `lunarscope-master.service` | `--password-file /etc/lunarscope/dashboard-password` added to `ExecStart` |

### `hash-password`

```text
$ lunarscope-master hash-password
New dashboard password:
Repeat the password:
$argon2id$v=19$m=19456,t=2,p=1$…$…
Put this line in /etc/lunarscope/dashboard-password (owner root:lunarscope, mode 640).
```

In a terminal it turns echo off with `stty -echo`, so the password isn't
shown, and asks twice. Piped input (`printf '…\n' | lunarscope-master
hash-password`) is read once, without prompts. Fewer than 12 characters is
refused.

## Setting it up on the master server

```bash
sudo /usr/local/bin/lunarscope-master hash-password | sudo tee /etc/lunarscope/dashboard-password >/dev/null
sudo chown root:lunarscope /etc/lunarscope/dashboard-password
sudo chmod 640 /etc/lunarscope/dashboard-password
sudo install -m 644 lunarscope-master.service /etc/systemd/system/lunarscope-master.service
sudo systemctl daemon-reload
sudo systemctl restart lunarscope-master
journalctl -u lunarscope-master -n 3    # "... dashboard login enabled"
```

(`tee` only receives the hash on stdout; the prompts go to stderr.)

To change the password, run the first line again and restart the master.
That also logs everyone out.

## Tests

Master: **158 tests** (was 133).

### New in `session.rs` (12)

| Test | Checks |
|------|--------|
| `hash_is_argon2id_with_default_parameters_and_verifies` | Format of the hash; right password matches, a slightly different one and an empty one don't |
| `same_password_gets_a_different_salt_each_time` | Random salt |
| `short_password_is_refused` | 11 characters refused, 12 accepted |
| `malformed_hash_never_matches` | Empty, plain text, broken PHC string |
| `password_file_is_read_and_trimmed` | Trailing newline is ignored |
| `plain_password_in_file_is_refused` | Error points to `hash-password` |
| `missing_password_file_is_an_error` | Error names the path |
| `login_checks_the_password` | `Login::check_password` |
| `session_is_valid_until_it_expires` | 64 hex characters; valid until 12 h, not after |
| `unknown_and_removed_tokens_are_invalid` | Unknown/empty token; logout of one session leaves the other |
| `tokens_are_stored_hashed_and_expired_ones_are_dropped` | Only SHA-256 in memory; expired sessions removed |
| `limiter_locks_after_five_failures_within_a_minute` | Locked at 5, open again after 60 s |

### New in `routes/login.rs` (12)

| Test | Checks |
|------|--------|
| `dashboard_pages_redirect_to_login_without_a_session` | `/`, `/server/a1`, `/server/unknown` → 303 `/login`, no data |
| `htmx_refresh_without_a_session_gets_hx_redirect` | 401 + `HX-Redirect: /login`, empty body |
| `without_password_file_the_dashboard_is_locked` | `/`, `GET /login`, `POST /login` → 403 with the explanation, no form |
| `login_page_shows_a_password_form` | Form, password field, no Log out button, `no-store` |
| `right_password_sets_a_safe_cookie_that_opens_the_dashboard` | 303 `/`; cookie has `Path=/`, `Max-Age=43200`, `HttpOnly`, `Secure`, `SameSite=Strict`; the cookie opens the dashboard, which has a Log out button |
| `wrong_password_is_refused_without_a_cookie` | Wrong, empty, and right-plus-a-space → 401, no cookie |
| `forged_or_old_cookies_do_not_open_the_dashboard` | Made-up token, empty value, other cookie |
| `session_cookie_is_found_among_other_cookies` | Works between other cookies; a cookie with a longer name ending in `lunarscope_session` doesn't count |
| `too_many_wrong_passwords_lock_the_login` | After 5 wrong, even the right password → 429, no cookie |
| `logout_ends_the_session_and_clears_the_cookie` | 303 `/login`, `Max-Age=0`, old cookie no longer works |
| `api_and_htmx_file_need_no_login` | `/static/htmx.min.js` 200; `/api/scan-result` still gives its own 401, not a redirect |
| `sessions_are_per_master_instance` | A token from one master doesn't work on another |

### Changed

- `main.rs`: new `password_file_is_optional`. `every_route_is_combined_in_app`
  now runs logged in and also covers `/login` and `/logout`.
  `serves_over_a_real_socket_and_shuts_down_gracefully` now checks that
  `/login` is served and `/` redirects.
- The dashboard and server page tests run through
  `routes::login::logged_in_app()`, which sets up a login and adds a valid
  session cookie to every request. Their checks are unchanged.

## Checks

Development machine (Fedora), rustc 1.99.1:

| Check | Result |
|-------|--------|
| `cargo test --locked` | ✅ 158 passed |
| `cargo clippy --all-targets --all-features --locked -- -D warnings` | ✅ |
| `cargo fmt --check` | ✅ |
| `cargo build --release --locked` | ✅ |

### Manual run

Release binary, `--listen 127.0.0.1:38200 --password-file <file>`, file made
with `hash-password` from a test password.

`hash-password` and startup:

| Action | Result |
|--------|--------|
| `hash-password` with "too short" | `the password must be at least 12 characters`, exit 1 |
| `hash-password x` | `hash-password takes no arguments` + usage, exit 1 |
| `hash-password` with a 19-character password | `$argon2id$v=19$m=19456,t=2,p=1$…` |
| Start with a plain password in the file | `… does not contain a password hash; create one with 'lunarscope-master hash-password'`, exit 1 |
| Start with the hash | `… agent registration disabled (no --admin-token-file), dashboard login enabled` |

With curl:

| # | Request | Answer |
|---|---------|--------|
| 1 | `GET /` | 303, `location: /login` |
| 2 | `GET /` with `HX-Request: true` | 401, `hx-redirect: /login` |
| 3 | `POST /login`, wrong password | 401, "Wrong password." |
| 4 | `POST /login`, right password | 303 to `/`, `set-cookie: lunarscope_session=…; Path=/; Max-Age=43200; HttpOnly; Secure; SameSite=Strict` |
| 5 | `GET /` with the cookie | 200, "Servers" and the Log out button |
| 6 | `POST /logout` | 303 to `/login`, cookie cleared (`Max-Age=0`) |
| 7 | `GET /` with the old cookie | 303 to `/login` |
| 8 | `POST /api/scan-result` without a key | 401 `{"error":"invalid or missing API key"}` (the API's own check, unchanged) |
| 9 | 4 more wrong passwords, then the right one | `401 401 401 401 429`, then 429 "Too many wrong passwords…" (the wrong password of step 3 was the first of the five) |

In a browser (Chromium, built-in browser pane): `/` opened the login page.
The login right after the curl test got the 429 message, as expected. After
the minute, the right password opened the dashboard ("No agents have
reported yet.", Log out button top right). Log out led back to the login
page, and `/` stayed on the login page.

After `SIGTERM` the master stopped normally (exit 0).

Not tested by hand: a session expiring after 12 hours while the dashboard is
open (the HTMX redirect is covered by
`htmx_refresh_without_a_session_gets_hx_redirect`, the expiry by
`session_is_valid_until_it_expires`).

## Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| `Secure` removed from the cookie | `right_password_sets_a_safe_cookie_that_opens_the_dashboard` |
| Middleware lets every request through | 6 tests, e.g. `dashboard_pages_redirect_to_login_without_a_session` |
| No lockout | `limiter_locks_after_five_failures_within_a_minute`, `too_many_wrong_passwords_lock_the_login` |
| Logout keeps the session | `logout_ends_the_session_and_clears_the_cookie` |
| Sessions never expire | `session_is_valid_until_it_expires` |
| Any password accepted | `login_checks_the_password`, `wrong_password_is_refused_without_a_cookie`, `too_many_wrong_passwords_lock_the_login` |
| Token stored instead of its hash | `tokens_are_stored_hashed_and_expired_ones_are_dropped` (and 29 others) |
| `layer` instead of `route_layer` (unknown paths need a login) | `unknown_path_answers_404`, `other_static_paths_are_404` |
| No `HX-Redirect` header | `htmx_refresh_without_a_session_gets_hx_redirect` |
| Short passwords allowed | `short_password_is_refused` |
| Password file content not checked | `plain_password_in_file_is_refused` |
| Cookie name matched with `ends_with` instead of exactly | `session_cookie_is_found_among_other_cookies` (this check was added after the first run missed it) |

All 12 caught.

## Not done

- No "remember me" and no way to see or end other sessions; logging out
  ends only your own session (a restart ends all).
- One password for one administrator, no user accounts.
- The other two points from the master review are still open: a check a
  module stops sending stays on the dashboard, and `cargo audit` /
  `cargo deny` haven't run yet (phase 4).

## Docs updated

- [code-overview.md](code-overview.md): login, new files, 158 tests.
- Steps 29, 30, 32 and 34: a short "Update 2026-11-16" note pointing here.
- [change-0.2.0-daily-scan-time.md](../phase-2-lunarscope-agent/change-0.2.0-daily-scan-time.md):
  the master is released as 0.2.0, not 0.1.1; its commit commands now point
  here.
- [README](../README.md): link to this file.

## Files to commit in `lunarscope-master`

```text
Cargo.toml
Cargo.lock
lunarscope-master.service
src/auth.rs
src/main.rs
src/session.rs                (new)
src/routes/mod.rs
src/routes/login.rs           (new)
src/routes/dashboard.rs       (25 h stale limit + tests logged in)
src/routes/server.rs          (tests logged in)
src/templates.rs
templates/base.html
templates/dashboard.html
templates/server.html
templates/not_found.html
templates/login.html          (new)
```

## Commit and tag (done by hand)

> **Update 2026-11-16:** Not committed separately. Master 0.2.0 is released
> together with 0.3.0; use the commands in [change-0.3.0-agent-management.md](change-0.3.0-agent-management.md). The commands below are kept
> for the record.

From `repos/lunarscope-master`:

```bash
git add Cargo.toml Cargo.lock lunarscope-master.service src templates
git status
git commit -m "Dashboard login with Argon2 password, sessions and lockout; stale after 25 h (v0.2.0)"
git pull --rebase origin main
git tag -a v0.2.0 -m "lunarscope-master v0.2.0"
git push origin main
git push origin v0.2.0
```
