# Change (0.8.0) — the e-mail server only in the config file

**Repo:** `lunarscope-master` 0.8.0 (uncommitted, together with 0.7.1)
**Date:** 2026-11-25
**Status:** Done — code, tests, live check, mutation checks; not committed yet

## The requests

1. First request: the e-mail server must only be configurable in the config
   file, not on the Settings page.
2. Refined while the work was going on: the **recipients, on/off, day/time and
   language** SHOULD be set on the page, and of the mail server **only the
   sender address** is shown on the page.

Why: an SMTP password should not sit in the database or pass through a web
form. The server is a matter for whoever runs the master (a file on the
machine); who gets the report and when is a matter for the admin on the page.

## Result

- `src/email.rs`: `SmtpFile` (from `--smtp-file`, format unchanged: host,
  port, security, username, password, from) is the only source of the server.
  `load()` reads only the page's settings from the database (`email_enabled`,
  `email_to`, `email_day`, `email_time`, `email_lang`, `email_last_sent`,
  `email_last_error`), never a server key. `store` and `store_server` are
  gone; `store_schedule` stores the page's part. `current()` = page settings
  from the database + server from the file; without the file there is no
  server.
- `src/routes/email.rs`: `EmailForm` has only enabled/to/day/time/lang.
  `from_form(stored, form)` keeps the server of `stored`. Switched on, it needs
  a server (`email_no_file`) and has to pass `problem()` (recipients, time);
  switched off anything may be saved. `save` calls `store_schedule`. Server
  fields posted to the page are ignored.
- `templates/email.html`: the form (on/off, day and time, recipients,
  language) and of the server only a `<dl class="facts">` with the sender
  address. Without the file a notice (`email_no_file`, `email_no_file_help`)
  and no test button.
- `install/smtp.toml.example`: comment updated. Texts `email_no_file`,
  `email_no_file_help` added (EN and NL), `email_test_help` reworded.
- Version 0.8.0.

### An old bug found on the way

Since 0.6.0 the language radio on the page showed the **dashboard** language,
not the language of the mail. The template context's `lang` (the dashboard
language) overwrote the view's `lang`. The view field is now called
`mail_lang`, and the template uses that. A regression check is in the page
test (see below).

### Migration

`migrations/0011_smtp_server_only_in_file.sql` deletes `email_host`,
`email_port`, `email_security`, `email_username`, `email_password` and
`email_from` from `settings`, so also an SMTP password that was stored in the
database. The page's settings (on/off, recipients, day, time, language, last
sent, last error) are kept.

## Tests

Master **375** tests, all passing.

| Test | Area |
|------|------|
| `routes::email::tests::the_schedule_is_set_on_the_page_and_of_the_server_only_the_sender_shown` | form saves the schedule; only the sender shown; language radio shows the mail's language |
| `routes::email::tests::server_fields_sent_to_the_page_are_ignored` | posted host, password, etc. change nothing |
| `routes::email::tests::switched_on_it_needs_the_file_and_good_recipients_switched_off_anything_goes` | `email_no_file`, bad recipients/time refused when on; off may be saved (assertion on the reason added after mutation 2) |
| `routes::email::tests::the_test_button_sends_with_the_file_and_shows_the_result` | test mail through a fake SMTP server |
| `routes::email::tests::read_only_users_cannot_see_or_change_it` | permissions |
| `email::tests::with_the_smtp_file_its_server_is_used_not_the_database` | old server keys in the database are ignored; no file, no server |
| `email::tests::settings_are_stored_and_read_back` | the server is never stored |
| `db::tests::migration_11_removes_the_smtp_server_but_keeps_the_pages_settings` | added after mutation 6: runs migrations to 10, fills all email keys, runs 0011 |

## Live check

Test master on `127.0.0.1:3078` with a fresh database and the example SMTP
file: the page shows the form and of the server only "Sender address
Lunarscope <lunarscope@example.nl>"; the startup log says "e-mail: SMTP server
127.0.0.1:587 (starttls) from ...". Without the file the page shows the notice
and no test button.

## Mutation checks

Each deliberate bug applied, the whole `cargo test` run, files restored
afterwards (checked with `cmp`).

| # | Mutation | Result |
|---|----------|--------|
| 1 | `load()` reads `email_host` from the database again | caught: `email::tests::with_the_smtp_file_its_server_is_used_not_the_database` |
| 2 | `from_form` skips the `email_no_file` check | **survived at first** (without a file `problem()` refuses it anyway, only with another message, and the test looked for text that is also in the page notice); assertion that the "Fill in the SMTP server" message is absent added; re-run: caught by `switched_on_it_needs_the_file_and_good_recipients_switched_off_anything_goes` |
| 3 | `from_form` skips `problem()` when switched on | caught: `switched_on_it_needs_the_file_and_good_recipients_switched_off_anything_goes` |
| 4 | `save` stores nothing (redirect kept) | caught: `the_schedule_is_set_on_the_page_and_of_the_server_only_the_sender_shown` and `switched_on_it_needs_the_file_and_good_recipients_switched_off_anything_goes` |
| 5 | template radio uses `lang` instead of `mail_lang` | caught: `the_schedule_is_set_on_the_page_and_of_the_server_only_the_sender_shown` |
| 6 | migration 0011 also deletes `email_to` | **survived at first** (no test ran the migration on a database with e-mail keys); added `migration_11_removes_the_smtp_server_but_keeps_the_pages_settings` (pattern of `migration_2_...`: `MIGRATOR.run_to(10, ...)`); re-run: caught |

4 of 6 caught at once; 2 survived and are caught after one extra assertion or
test.

## On an existing master

Before updating, **put the SMTP server in `/etc/lunarscope/smtp.toml`** (see
`install/smtp.toml.example`; the unit passes `--smtp-file`). Server settings
that were saved on the page are **deleted** by the migration, also the
password, and cannot be recovered from the master. Recipients, on/off, day,
time and language stay, so the weekly mail goes on once the file is there; if
the file is missing, the mail is not sent and the page says why.
