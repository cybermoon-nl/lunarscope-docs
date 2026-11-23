# Change (0.6.1) — CSRF tokens on every dashboard change

**Repo:** `lunarscope-master` 0.6.1
**Date:** 2026-11-23
**Status:** Done — code, tests, mutation checks, checked live on a test
master; not committed yet

## Why

[architecture-as-built.md](../architecture-as-built.md), section 8, item 4:
dashboard forms had **no CSRF token**. The only protection was the
`SameSite=Strict` session cookie and the rule that changes are POST only. That
works in current browsers, but it is one layer. A browser that ignores
`SameSite`, or a site on the same registrable domain, could make a logged-in
admin add a user, reset a password or delete a user. Semgrep also reported
the missing token (see [fix-0.6.1-semgrep-blocking.md](fix-0.6.1-semgrep-blocking.md)).

## What was built

- **Token** (`src/session.rs`): `csrf_token(session_token)` is the SHA-256 hex
  of `"csrf:" + session token`. 64 hex characters, one per session.
- **Check** (`src/routes/login.rs`, `check_csrf`), called in `require_login`
  before the viewer check, so it applies to every route behind the login:
  - `GET`, `HEAD`, `OPTIONS` pass.
  - Other methods need the token in the header `X-CSRF-Token` **or** in the
    form field `csrf`. A header, when present, decides (a wrong header is not
    rescued by a right field).
  - Compare is constant-time (`crate::auth::constant_time_eq`).
  - Wrong or missing: **403** with the normal page and the text
    `csrf_failed` (EN and NL: the form is no longer valid, open the page again).
    The refusal is logged on stderr.
- **Body limit**: to read the field the body is buffered, at most
  `MAX_CSRF_BODY_BYTES` = 256 KiB. A bigger body gets **413** and is not
  looked at further. After the check the body is put back for the handler.
- **Field search** (`form_csrf`): splits on `&` and takes the pair that starts
  with exactly `csrf=`. `xcsrf=` or `mycsrf=` do not count. The token is hex,
  so it needs no URL decoding.
- **Logout** (`POST /logout`) is outside `require_login`, so it checks the
  token itself (header or field). Without a valid token: 403, the session
  stays. Without a session there is nothing to check.
- **Templates** (`src/templates.rs`, `templates/*.html`): `Ui.csrf` is taken
  from the session cookie and put in every template context as `csrf`. All
  **24** dashboard POST forms got
  `<input type="hidden" name="csrf" value="{{ csrf }}">`.
- **Login forms are not changed** (3 forms: password, code, recovery key).
  There is no session yet, so no token exists; they are protected by the
  pending-login cookie, the per-IP lockout and `SameSite=Strict`. A forged
  login only logs the victim in as the attacker's own account at most, which
  needs the attacker's password and gains nothing here.

| Part | Where |
|------|-------|
| `csrf_token` | `src/session.rs` |
| `CSRF_HEADER`, `MAX_CSRF_BODY_BYTES`, `csrf_of`, `form_csrf`, `check_csrf`, `csrf_refused`, `logout` | `src/routes/login.rs` |
| `Ui.csrf`, context `csrf` | `src/templates.rs` |
| Hidden field in 24 forms | `templates/*.html` |
| Text `csrf_failed` (EN and NL) | `src/i18n.rs` |

No new crates, no migration, no stored state.

## Design decisions

- **A hash of the session token, nothing stored.** The token follows from the
  session, so there is no table, nothing to expire and nothing to clean up. A
  new login is a new session and a new token. The `"csrf:"` prefix makes it a
  different value from the hash the session store uses as its key
  (`hash_api_key(token)`), so one never stands in for the other.
- **It does not leak the session.** SHA-256 cannot be turned back into the
  session token, so a token that shows up in a page, a log or a screenshot
  does not give the cookie. A page in the HTML is readable by the user and by
  scripts on the page only, like any CSRF token.
- **Header or field.** Plain forms send the field. HTMX and `fetch` calls can
  send the header without touching each body. The header wins when present.
- **Fail closed.** No session cookie, no token, a wrong token, or a body that
  is too big to check: the change is not done.
- **Body limit.** The check must read the body before the handler. Without a
  limit a big upload could fill memory. 256 KiB is far above any form of the
  dashboard.
- **Checked in `require_login`**, not per route, so a new route cannot forget it.
- **Constant-time compare**, the same function used for the API key.
- **`SameSite=Strict` stays.** The token is a second layer, not a replacement.

## Tests

Master **366** tests, all passing (365 from the change, plus one added by the
mutation check below). `cargo fmt --check` and
`cargo clippy --all-targets -- -D warnings`: clean. Test helpers:
`logged_in_app_as` adds the header; `post_with` adds the field;
`post_without_csrf` sends neither.

| Test | Area |
|------|------|
| `routes::login::tests::every_form_on_the_pages_carries_the_csrf_token_of_the_session` | every page with a POST form has the field with the session's token |
| `routes::login::tests::a_change_without_the_right_csrf_token_is_refused` | missing and wrong token: 403, nothing changed; header and field both work |
| `routes::login::tests::a_form_too_big_to_check_is_refused` | body over the limit: 413 |
| `routes::login::tests::the_csrf_field_is_found_by_its_exact_name` | `xcsrf=` does not count |
| `routes::login::tests::logout_ends_the_session_and_clears_the_cookie` | also: logout without token is 403 |
| `session::tests::the_csrf_token_is_not_the_hash_the_sessions_are_stored_under` | added after mutation M5 survived |

### Checked live

A temporary master on `127.0.0.1:3077` with a temporary database (not the
service on port 3030):

- All forms on `/settings` carry a 64-character hex token.
- A forged `fetch` POST to `/settings/users` without token: **403** with the
  Dutch "niet meer geldig" text; no user was added.
- Normal **Save** on Settings: redirect to `?saved=1`.
- The **Logout** button works.

### Mutation checks

Each deliberate bug was applied, the whole `cargo test` run, and the file
restored (and touched, compared with a copy).

| # | Mutation | Result |
|---|----------|--------|
| M1 | `check_csrf` lets every method through | caught: `a_change_without_the_right_csrf_token_is_refused` |
| M2 | header path accepts any header value | caught: same test |
| M3 | form path accepts any value (no compare) | caught: same test |
| M4 | `form_csrf` finds `csrf=` anywhere in a pair | caught: `the_csrf_field_is_found_by_its_exact_name` |
| M5 | `csrf_token` hashes the token without the prefix | **survived** at first; added `the_csrf_token_is_not_the_hash_the_sessions_are_stored_under`; re-run: caught |
| M6 | `require_login` skips `check_csrf` | caught: `a_change_without_the_right_csrf_token_is_refused` |
| M7 | `logout` skips its check | caught: `logout_ends_the_session_and_clears_the_cookie` |
| M8 | hidden field removed from `templates/users.html` | caught: `every_form_on_the_pages_carries_the_csrf_token_of_the_session` |
| M9 | too-big body answers 403 instead of 413 | caught: `a_form_too_big_to_check_is_refused` |
| M10 | `Ui.csrf` always empty | caught: `every_form_on_the_pages_carries_the_csrf_token_of_the_session` |

9 of 10 caught at first; M5 survived (it would only be a weakness if the
session store key were exposed, which it is not) and is caught after adding a
small test.
