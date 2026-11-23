# Change (0.6.1) — Recovery key for two-step login

**Repo:** `lunarscope-master` 0.6.1
**Date:** 2026-11-23
**Status:** Done — code, tests, mutation checks, checked live on a test
master; not committed yet

## Why

Reported problem: right after turning on two-step login, the Account page
showed a code field again. That field was meant for turning two-step login
**off**, but it looked as if the code was asked a second time.

Also, the only way back after losing a phone was an admin reset or the CLI.
A user now has a **recovery key** of their own.

## What was built

### 1. Account page after setup

- Right after turning it on, the page shows only a notice and the button
  **Download recovery key (PDF)**. There is no code field.
- Turning it off is folded in a `<details>` element, so it is not in the way.

### 2. The recovery key (PDF)

- The recovery key **is the TOTP secret** (user's choice: "dit mag gewoon die
  code zijn"). No second secret to store.
- `POST /account/recovery` gives a PDF of one page, always light so it can be
  printed. It has:
  - the user name and the master host,
  - the key in groups of four,
  - what to do when the phone is lost,
  - a QR code to add the same account to a new phone,
  - advice to keep it safe.
- **Without a code only for 10 minutes after turning on** (`FreshMfa`, in
  memory, gone after a restart). Afterwards a current code is needed (one-time
  use via `use_mfa_step`), so a browser that is left logged in cannot get the
  key. Turning two-step login off closes the window.
- Header `Cache-Control: no-store`, file name `lunarscope-recovery-key.pdf`.
  Audit line "recovery key downloaded".

### 3. Logging in with the recovery key

- At the code step, after the password: **"Lost your phone? Use your recovery
  key"** (`POST /login/mfa/recovery`).
- Spaces, dashes and case do not matter. The compare is constant-time
  (`totp::is_recovery_key`).
- **Right key:** two-step login is turned off, the user is logged in and sent
  to `/account?done=recovered`, with a notice to set it up again. Setting it up
  again makes a new secret, so the old sheet stops working. Audit lines
  "two-step login off with recovery key" and "logged in" with detail
  "admin, recovery key".
- **Wrong key:** counts for the per-IP lockout and for the 5 attempts of the
  pending login (the same `wrong_attempt` as wrong codes). Audit line "login
  recovery key wrong".
- It needs the pending-login cookie, so without the password step it does
  nothing. A locked address gets 429.

| Part | Where |
|------|-------|
| `is_recovery_key`, `qr_modules` | `src/totp.rs` |
| `FreshMfa` (10 minute window) | `src/session.rs` |
| `recover`, `wrong_attempt`, `start_session` with `to` | `src/routes/login.rs` |
| `recovery_pdf`, `fresh` | `src/routes/account.rs` |
| `recovery_sheet`, `finish` (refactored, shared with the report) | `src/report_pdf.rs` |
| Account page, code step | `templates/account.html`, `templates/login.html` |
| Texts `recovery_*`, `wrong_recovery` (EN and NL) | `src/i18n.rs` |
| Routes `POST /login/mfa/recovery`, `POST /account/recovery` | `src/main.rs` |

No new crates and no migration.

## Design decisions

- **The key is the secret.** Simple for the user (one thing to keep), and the
  same sheet adds the account to a new phone. The price: anyone with the sheet
  has both the key and the codes, so the sheet must be kept like a password.
- **Download window of 10 minutes, in memory.** Long enough to click the
  button after setup; short enough that an open browser later is not enough.
  After a restart the window is gone, which is the safe side.
- **After the window, a current code** that is used once (`use_mfa_step`), the
  same rule as turning off.
- **Turning off closes the window**, so a new setup starts fresh.
- **Using the key turns two-step login off**, and the user must set it up
  again. The new secret makes the printed sheet useless.
- **Wrong keys count like wrong codes** (shared `wrong_attempt`), so the key
  cannot be guessed from one address or within one pending login.
- **`no-store`** so the key is not kept in a cache.
- **Always light PDF**, for printing.
- **The QR code is not decoded in a test.** It comes from the same `qrcode`
  library as the on-screen QR (`qr_modules` gives the modules; the PDF draws
  them).

## How to use it

- **After turning on two-step login:** click "Download recovery key (PDF)",
  print it or keep it in a safe place.
- **Later:** Account → "Download the recovery key again" (asks a current code).
- **Lost phone:** log in with the password, choose "Lost your phone? Use your
  recovery key", type the key (any spacing and case). Then set up two-step
  login again on the Account page.

## Tests

Master **360** tests, all passing. `cargo fmt --check` and
`cargo clippy --all-targets -- -D warnings`: clean.

New tests for this change:

| Test | Area |
|------|------|
| `routes::login::tests::the_recovery_key_logs_in_and_turns_two_step_login_off` | right key, redirect, audit |
| `routes::login::tests::without_the_password_step_the_recovery_key_does_nothing` | needs pending login |
| `routes::login::tests::wrong_recovery_keys_count_like_wrong_codes` | 5 tries |
| `routes::login::tests::a_locked_address_cannot_use_the_recovery_key` | per-IP lockout, 429 |
| `routes::login::tests::the_recovery_key_pdf_needs_a_code_except_right_after_turning_on` | PDF, code rule, headers, audit |
| `routes::login::tests::turning_off_closes_the_download_without_code` | window closed |
| `routes::login::tests::a_user_sets_up_two_step_login_on_the_account_page` | extra assertions: no code field after setup |
| `totp::tests::the_secret_works_as_recovery_key_however_it_is_typed` | key matching |
| `totp::tests::qr_modules_are_a_square` | QR modules |
| `session::tests::recovery_download_without_code_only_just_after_turning_on` | `FreshMfa` window |

### Checked live

A test master on `127.0.0.1:3077` with a temporary database (not the
service on port 3030):

- Logged in with the password, then used the recovery key **typed in lower
  case with spaces**: logged in on Account with the notice, two-step login off.
- Set it up again with a code from an **independent Python TOTP
  implementation**: the page shows only the download box, no code field.
- Downloaded the PDF (200, correct file name) and rendered it: 1 page, all
  parts present.
- The QR code in the PDF was **not decoded with a scanner** (no tool
  available), but it comes from the same `qrcode` library as the on-screen QR.

### Mutation checks

Each deliberate bug was applied, the whole `cargo test` run, and the file
restored (and touched).

| # | Mutation | Caught by |
|---|----------|-----------|
| R1 | Drop the `!a.is_empty()` guard | `the_secret_works_as_recovery_key_however_it_is_typed` |
| R2 | Compare `a` with `a` | 3 tests |
| R3 | `recover` skips the limiter check | first survived; added `a_locked_address_cannot_use_the_recovery_key`; re-run: caught |
| R4 | `recover` skips `clear_mfa` | caught |
| R5 | `recover` redirects to `/` | not applied (pattern not unique); the redirect is asserted in `the_recovery_key_logs_in_and_turns_two_step_login_off` |
| R6 | PDF always needs a code | caught |
| R7 | PDF never needs a code | caught |
| R8 | Turning on does not open the window | caught (3 tests) |
| R9 | Turning off does not close it | caught |
| R10 | PDF ignores `use_mfa_step` (reused code) | caught |
| R11 | `is_open` uses `>=` | caught |
| R12 | Wrong key not counted by the limiter | caught |

11 of 12 caught by tests; R3 survived at first and is caught after adding a
test; R5 could not be applied and is covered by an assertion instead.
Pitfall (as before): touch the file after restoring, or cargo may test a
stale build.
