# Change (0.6.0) — Two-step login (TOTP) and the report by e-mail

**Repo:** `lunarscope-master` 0.6.0
**Date:** 2026-11-23
**Status:** Done — code, tests, mutation checks, checked live on a test
master; not committed yet

## Why

When the project plan (`Projectplan.pdf`) was checked against the code on
2026-11-23, two items were missing:

- p.5, in scope: **"dashboard login with MFA"** (deliverable 1.3 on p.6)
- p.5, in scope: **"emailed reports on a schedule"** (deliverable 1.6 on p.6)

Both are now built.

## What was built

### 1. Two-step login (TOTP, RFC 6238)

- A user turns it on on the **Account** page (`GET /account`, reached via
  the user name in the sidebar): scan the QR code or type the secret into an
  authenticator app, enter the first code, and it is on
  (`POST /account/mfa`).
- Login then has two steps: the password opens a code step
  (`/login/mfa`, `POST /login/mfa`). The password alone no longer opens the
  dashboard.
- Turning it off (`POST /account/mfa/off`) needs a current, fresh code.
- Lost phone: an admin resets it per user (`POST /settings/users/{id}/mfa/off`,
  button in Settings → Users), or on the server with the CLI:
  `lunarscope-master reset-mfa <name> [--db path]`.
- Setting **require two-step login** (`POST /settings/users/require-mfa`,
  checkbox in Settings → Users): users without it are sent to `/account`
  until they have set it up. Read-only users (viewers) may use `/account`
  too, so they can do that.
- Users page has an MFA column.

| Part | Where |
|------|-------|
| HMAC-SHA1, base32, verify, otpauth URI, QR SVG | `src/totp.rs` |
| `users.totp_secret`, `users.totp_last_step` | `migrations/0009_mfa.sql` |
| `mfa_of`, `set_mfa`, `clear_mfa`, `clear_mfa_by_name`, `use_mfa_step` | `src/db/users.rs` |
| `PendingLogins` (code step), `MfaSetups` (setup secret) | `src/session.rs` |
| Login steps, cookie `lunarscope_mfa`, `require_login`, `viewer_may` | `src/routes/login.rs` |
| Account page | `src/routes/account.rs`, `templates/account.html` |
| Admin reset, require setting | `src/routes/users.rs`, `templates/users.html` |
| CLI `reset-mfa` | `src/main.rs` |
| Code step | `templates/login.html` |

### 2. The report by e-mail

- **Settings → E-mail** (`GET/POST /settings/email`): switch on, SMTP
  server, port, security (`starttls`, `tls` or `none`), user name,
  password, from, to, weekday (or daily) and time.
- **Send test mail** (`POST /settings/email/test`) sends right now and
  redirects to `?done=sent` or `?done=failed`.
- The mail has a short summary in the text (counts per severity, number of
  servers, the most urgent problems) and the **full PDF report attached**
  (`lunarscope-report-YYYY-MM-DD.pdf`). When the master runs with
  `--public-url`, the text also has an Online link to the report.

| Part | Where |
|------|-------|
| `EmailSettings` (stored as `email_*` keys in the settings table), `is_due`, summary text, message with PDF (lettre), `send_smtp`, `send_now`, `tick`, `spawn` | `src/email.rs` |
| Settings page and routes | `src/routes/email.rs`, `templates/email.html`, `templates/settings_tabs.html` |

`send_now` records `email_last_sent` and `email_last_error` and writes audit
lines. `spawn` starts a task that calls `tick` every 60 s.

### New crates

| Crate | Why |
|-------|-----|
| `hmac` 0.13, `sha1` 0.11 | HMAC-SHA1 for TOTP (RFC 6238) |
| `qrcode` 0.15 (only the `svg` feature) | QR code for the authenticator app, drawn as SVG, no image library |
| `lettre` 0.11.24 (`builder`, `smtp-transport`, `tokio1-rustls-tls`, `hostname`) | SMTP client and message building with an attachment. rustls (pure Rust TLS) instead of native TLS, so no system OpenSSL is needed |

`deny.toml` now allows the licence **0BSD**, which `quoted_printable` (a
lettre dependency) uses.

## Design decisions

### Two-step login

- **SHA-1, 6 digits, 30 seconds**: the defaults every authenticator app
  supports. Other settings are silently ignored by some apps.
- **±1 step of drift** (`ALLOWED_DRIFT = 1`): the code from the step before
  or after is accepted, for a phone clock that is a bit off.
- **A code works once.** The last used step is stored (`totp_last_step`); a
  code is only accepted for a step newer than that. Marking a step as used
  is one atomic `UPDATE ... WHERE totp_last_step IS NULL OR totp_last_step < ?`,
  so two requests with the same code cannot both succeed.
- **The pending login is only in memory**: 5 minutes to enter the code,
  at most 5 wrong codes, then the password is asked again. Nothing about it
  is written to the database. Its cookie `lunarscope_mfa` has `Path=/login`,
  so it is not sent to the rest of the dashboard.
- **Wrong codes count toward the per-IP lockout** of the password step, so
  the code cannot be guessed from the same address.
- **Turning it off needs a fresh code**, so a stolen session alone cannot
  remove the second step.
- **Lost phone**: admin reset in Settings → Users, and `reset-mfa` on the
  server for when the only admin is locked out.
- **Require for everyone** is a setting (`require_mfa`).
- **The secret is stored in the database as plain base32.** The server must
  compute the codes, so it cannot be a hash. It is protected by the
  permissions on the database file, like the other secrets in it.
- **Setup secret**: the secret shown during setup lives in memory for 10
  minutes (`MfaSetups`) and is only stored once the first code is correct.

### E-mail

- **SMTP password** is stored in the settings table (like the other
  settings) and is **never sent to the page**. An empty password field keeps
  the stored one; the checkbox `clear_password` removes it.
- **Schedule in the master's time zone**: due when it is switched on and
  usable, the weekday fits (or daily), the local time is at or after the
  chosen `HH:MM`, and nothing was sent yet today.
- **Later the same day if the master was down**: because the rule is "at or
  after the time", a master that starts at 09:00 sends a 08:00 report then.
- **At most once per day.** After a failure `tick` waits 15 minutes
  (`RETRY_AFTER`) and tries again; a failed attempt does not set `last_sent`.
- **The test send does not count as the scheduled one** (it passes no date to
  `send_now`), so a test in the morning does not stop the report. The test
  button redirects to `?done=sent|failed`, so reloading the page does not
  send again.
- **A short summary plus the PDF**: the mail text can be read on a phone;
  the details are in the attachment. The list of urgent problems in the text
  is cut at 10 lines with a "+n" line that points to the PDF.

## How to use it

- **Turn on two-step login:** click your user name in the sidebar → Account
  → scan the QR code → enter the code → on.
- **Require it for everyone / reset a user:** Settings → Users (tick
  "require", or the reset button next to the user).
- **Lost phone, no admin can log in:**
  `lunarscope-master reset-mfa <name> --db <path to the database>`.
- **Report by e-mail:** Settings → E-mail. Fill in the server and the
  addresses, choose the day and time, switch it on, and use "Send test mail"
  to check it.

## Tests

Master **351** tests, all passing. `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check`:
clean.

New tests for this change:

| Test | Area |
|------|------|
| `totp::tests::hotp_matches_rfc_4226` | HOTP test vectors |
| `totp::tests::codes_match_the_rfc_6238_test_vectors` | TOTP test vectors |
| `totp::tests::base32_round_trips_and_matches_rfc_4648` | base32 |
| `totp::tests::new_secrets_are_random_160_bit_base32` | secret generation |
| `totp::tests::verify_accepts_the_current_and_neighbouring_codes_only` | ±1 step |
| `totp::tests::verify_ignores_spaces_and_refuses_other_input` | input handling |
| `totp::tests::a_code_works_only_once` | one-time use |
| `totp::tests::otpauth_link_names_the_user_and_the_master` | otpauth URI |
| `totp::tests::qr_code_is_an_svg_and_the_secret_is_grouped` | QR SVG |
| `db::users::tests::two_step_login_is_set_used_once_and_cleared` | database functions |
| `session::tests::pending_login_expires_and_ends_after_five_wrong_codes` | pending login |
| `routes::login::tests::with_two_step_login_the_password_alone_does_not_open_the_dashboard` | login step 1 |
| `routes::login::tests::the_right_code_logs_in_once_and_a_wrong_one_does_not` | login step 2 |
| `routes::login::tests::after_five_wrong_codes_the_password_is_asked_again` | 5 tries |
| `routes::login::tests::wrong_codes_count_for_the_address_lockout` | per-IP lockout |
| `routes::login::tests::a_user_sets_up_two_step_login_on_the_account_page` | account page, turn on and off |
| `routes::login::tests::when_required_a_user_without_two_step_login_can_only_set_it_up` | require setting |
| `routes::login::tests::an_admin_can_turn_off_two_step_login_of_a_user_but_a_viewer_cannot` | admin reset |
| `tests::reset_mfa_command_turns_it_off_in_the_database` | CLI |
| `tests::reset_mfa_takes_a_name_and_a_database` | CLI arguments |
| `email::tests::settings_are_stored_and_read_back` | storage |
| `email::tests::problems_name_what_is_missing` | usable check |
| `email::tests::due_on_the_day_from_the_time_and_once` | schedule |
| `email::tests::the_time_counts_in_the_masters_time_zone` | time zone |
| `email::tests::the_schedule_sends_once_on_the_day_and_retries_after_a_failure` | tick, retry |
| `email::tests::the_mail_has_a_summary_and_the_pdf` | message |
| `email::tests::the_mail_links_to_the_report_with_a_public_url` | Online link |
| `email::tests::without_urgent_problems_the_mail_says_so` | empty summary |
| `email::tests::long_lists_are_cut_in_the_mail` | 10 lines |
| `email::tests::it_really_goes_out_over_smtp` | fake SMTP server |
| `email::tests::a_refused_connection_is_an_error_that_is_kept` | failure kept |
| `routes::email::tests::settings_are_saved_and_the_password_never_shown` | password handling |
| `routes::email::tests::switched_on_it_must_be_usable_switched_off_it_may_be_half_done` | validation |
| `routes::email::tests::the_test_button_sends_now_and_shows_the_result` | test send, redirect |
| `routes::email::tests::read_only_users_cannot_see_or_change_it` | permissions |

### Checked live

A test master on `127.0.0.1:3077` with a temporary database (not the
service on port 3030):

- Two-step login set up with a code computed by an **independent Python
  TOTP implementation**.
- Logging in again needed the code.
- The same code a second time got 401.
- The test e-mail arrived at a fake SMTP server, with Dutch text and a valid
  6.4 kB PDF attached, named `lunarscope-report-2026-11-23.pdf`.

### Mutation checks

Each deliberate bug was applied, the whole `cargo test` run, and the file
restored (and touched).

| # | Mutation | Caught by |
|---|----------|-----------|
| M1 | `code_at`: no `& 0x7f` on the offset byte | `codes_match_the_rfc_6238_test_vectors`, `hotp_matches_rfc_4226` |
| M2 | `verify`: `step > last` → `step >= last` | `a_code_works_only_once` |
| M3 | `ALLOWED_DRIFT` 1 → 2 | `verify_accepts_the_current_and_neighbouring_codes_only` |
| M4 | `use_mfa_step`: `<` → `<=` | `two_step_login_is_set_used_once_and_cleared` |
| M5 | Password step opens a normal session although MFA is on | 5 tests, among them `with_two_step_login_the_password_alone_does_not_open_the_dashboard` |
| M6 | Wrong code not recorded in the IP lockout | `wrong_codes_count_for_the_address_lockout` |
| M7 | `record_wrong`: `>=` → `>` (6 tries) | `after_five_wrong_codes_the_password_is_asked_again`, `pending_login_expires_and_ends_after_five_wrong_codes` |
| M8 | `require_login` ignores `require_mfa` | `when_required_a_user_without_two_step_login_can_only_set_it_up` |
| M9 | Viewers may not use `/account` | `a_user_sets_up_two_step_login_on_the_account_page` |
| M10 | Turning off accepts any code | `a_user_sets_up_two_step_login_on_the_account_page` |
| M11 | `is_due`: `>=` → `>` on the time | `due_on_the_day_from_the_time_and_once`, `the_schedule_sends_once_on_the_day_and_retries_after_a_failure`, `the_time_counts_in_the_masters_time_zone` |
| M12 | `is_due`: no "already sent today" check | `due_on_the_day_from_the_time_and_once`, `the_schedule_sends_once_on_the_day_and_retries_after_a_failure` |
| M13 | `tick`: no retry delay after a failure | `the_schedule_sends_once_on_the_day_and_retries_after_a_failure` |
| M14 | Empty password field wipes the stored password | `settings_are_saved_and_the_password_never_shown` |
| M15 | Urgent list not cut at 10 lines | `long_lists_are_cut_in_the_mail` |
| M16 | `tick` does not record today as sent | `the_schedule_sends_once_on_the_day_and_retries_after_a_failure` |
| M17 | MFA cookie `Path=/login` → `Path=/` | 4 tests, among them `with_two_step_login_the_password_alone_does_not_open_the_dashboard` |

17 of 17 caught. Pitfall (as before): touch the file after restoring, or
cargo may test a stale build. M5 first failed to compile (the user value
was moved); it was redone with a clone so that the build is valid and the
test failures are real.
