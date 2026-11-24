# Change (0.7.0) — SMTP server from a config file

**Repo:** `lunarscope-master` 0.7.0
**Date:** 2026-11-24
**Status:** Done — code, tests, mutation checks; **not tested against a real
SMTP server** (no SMTP server available yet); not committed yet

## Why

Until 0.6.1 the SMTP server, user name and **password** were typed on the
Settings → E-mail page and stored in the database. A password in the database
ends up in backups. Now it can live in a file that only root and the master
can read, like the other secrets in `/etc/lunarscope`.

## What was built

### 1. The file

- `--smtp-file <path>` on the master. Installed as `/etc/lunarscope/smtp.toml`
  (`install/smtp.toml.example` is the template).
- Fields (TOML, `deny_unknown_fields`): `host`, `port` (default 587),
  `security` (`starttls` default, `tls` or `none`), `username`, `password`,
  `from`.
- `load_smtp_file` refuses the file when:
  - other users may read it (`mode & 0o007 != 0`), with the advice
    "chmod 640";
  - `host` is empty, `port` is 0, `security` is not one of the three, or
    `from` is not a mailbox;
  - there is a `username` without a `password`.
- **Missing file** = warning in the log; the master runs without e-mail
  (the page keeps its normal form). **Bad or readable file** = startup error,
  so a mistake is seen at once.
- The startup log has a line saying which SMTP file is used.

### 2. Settings → E-mail with a file

- The server is shown **read-only** (a `<dl class="facts">`) with the path of
  the file; the password field is replaced by a note that it is in the file.
- `from_form` ignores the server fields of the form when a file is set.
- `save` then stores **only the schedule** (on/off, recipients, day, time,
  language) with `store_schedule`. The server and the password are never in
  the database.
- `current(state)` gives the settings in use: the database with the server of
  the file on top. The weekly `tick`, the test button and the page use it.
- `store` is split into `store_server` and `store_schedule`.

### 3. Service files

`lunarscope-master.service` and `scripts/install-dev-service.sh` pass
`--smtp-file /etc/lunarscope/smtp.toml`. Without the file the master only
warns, so existing installs keep working.

| Part | Where |
|------|-------|
| `SmtpFile`, `load_smtp_file`, `EmailSettings::with_file`, `current`, `store_server`, `store_schedule` | `src/email.rs` |
| `--smtp-file`, `AppState.smtp_file`, log line | `src/main.rs` |
| `from_form(stored, form, file)`, `save`, view field `smtp_file` | `src/routes/email.rs` |
| Read-only server block | `templates/email.html` |
| Texts `email_server_file`, `email_server_file_help`, `email_password_in_file` (EN and NL) | `src/i18n.rs` |
| Template | `install/smtp.toml.example` |

No new crates and no migration.

## Design decisions

- **File over database for the password.** The file has mode 640 and the
  master checks it; the database is copied in backups.
- **Strict at startup, lenient when missing.** A file that is there but wrong
  stops the master (better than a report that silently never arrives); no
  file just means no file-based setup.
- **The schedule stays in the page.** Recipients, day and time are not secret
  and are changed often; only the server part moves to the file.
- **The form ignores server fields** instead of rejecting them, so an old
  browser tab cannot overwrite anything.

## Tests

Master **371** tests, all passing (`cargo fmt --check` and clippy clean).

| Test | Area |
|------|------|
| `email::tests::the_smtp_file_is_read_with_defaults` | defaults, fields |
| `email::tests::a_bad_or_readable_smtp_file_stops_the_master` | mode, empty host, port, security, from, user without password |
| `email::tests::with_the_smtp_file_its_server_is_used_not_the_database` | `current` and `with_file` |
| `routes::email::tests::with_the_smtp_file_the_server_is_read_only_and_not_stored` | page, save, test mail through the file's server |
| `routes::email::tests::with_the_smtp_file_empty_server_fields_in_the_form_are_fine` | added after mutation 11 (see below) |
| `bad_args_are_errors` (main.rs, extended) | `--smtp-file` arguments |

### Mutation checks

Each deliberate bug applied, the whole `cargo test` run, the file restored.

| # | Mutation | Result |
|---|----------|--------|
| 9 | `load_smtp_file` skips the permission check | caught: `a_bad_or_readable_smtp_file_stops_the_master` |
| 10 | `save` calls `email::store` with the file set | caught: `with_the_smtp_file_the_server_is_read_only_and_not_stored` |
| 11 | `from_form` ignores the file (no `with_file`) | **survived at first** (the form in the test was full, nothing visible); added `with_the_smtp_file_empty_server_fields_in_the_form_are_fine`; re-run: caught |
| 12 | `current()` ignores `smtp_file` | caught: `with_the_smtp_file_its_server_is_used_not_the_database` and the route test |

3 of 4 caught at once; 1 survived and is caught after one extra test.

### Not tested

The SMTP file was **not tried against a real SMTP server**. The route test
uses the fake SMTP server of the test suite (`fake_smtp`), which proves that
the mail goes through the server of the file, but not STARTTLS or a login with
a real provider. To do once a server exists.
