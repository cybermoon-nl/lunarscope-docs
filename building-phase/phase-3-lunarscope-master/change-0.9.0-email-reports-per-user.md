# Change (0.9.0) — the e-mail report per user

**Repo:** `lunarscope-master` 0.9.0 (uncommitted, on top of the committed 0.8.0)
**Date:** 2026-11-25
**Status:** Done — code, tests, live check, mutation checks; not committed yet

## The requests

As they came:

1. The times in the e-mail settings must follow the **time format of
   Settings → General** (24 h or AM/PM).
2. **Every user sets their own report**, not one global report for the whole
   master.
3. Added while the work was going on: also an option **"every 1st of the
   month"**.

## Result

- **Migration** `migrations/0012_email_reports_per_user.sql`: new table
  `email_reports` (`user_id` primary key, references `users` with
  `ON DELETE CASCADE`; `enabled`, `recipients`, `day`, `time`, `lang`,
  `last_sent`, `last_error`, `last_error_at`). All `email_%` keys are deleted
  from `settings`.
- `src/email.rs`: `EmailSettings.last_error_at` (Unix time of the last
  failure). `load(pool, user_id)`, `store_schedule(pool, user_id, s)` (upsert),
  `record(pool, user_id, ...)` (an UPDATE; a success clears the error),
  `current(state, user_id)`, `all(state)` (every user's report with the
  server, ordered by user name; the SQL comes from a `report_select!` macro
  because sqlx needs static query text). `send_now(state, (user_id,
  username), ...)` writes "username: ..." in the audit log. `tick` keeps a
  retry time **per user** and returns how many reports it tried.
- **Monthly:** `DAYS` has "monthly" as index 8 (weekdays stay 1..7);
  `is_due` treats it as day 1 of the month in the master's time zone.
- `src/routes/email.rs`: `ReportView` for the Account page; `time_choices(
  current, hour12)` (every 15 minutes, labelled with `time::clock`, plus the
  saved time if it is between two steps); `EmailView` for the admin overview.
  Routes: `POST /account/email` (save) and `POST /account/email/test` (test
  send of your own report; any logged-in user, also read-only). The old
  `POST /settings/email` and `/settings/email/test` are removed; `main.rs` and
  the route table in the docs are updated.
- `src/routes/account.rs`: the report panel on the Account page, notices
  `?done=report_saved|report_sent|report_failed` with the `#report` anchor.
- Templates: `account.html` has the panel (on/off, day including "every 1st
  of the month", time list, recipients, language, only the sender address of
  the server, test button only with the SMTP file; an error is shown with its
  time). `email.html` is now an **overview for admins** of everyone's report
  (user, on/off, when, to, language, last sent or failed). Nothing can be
  changed there.
- Texts (EN and NL): `day_monthly`, `email_own_help`, `email_per_user_help`,
  `email_enabled_short`, `email_to_short`, `email_failed_short`,
  `email_no_reports`; `email_sub` reworded.
- Version 0.9.0.

### Time format

The time list on the Account page and the "when" column in the overview use
`time::clock` with the `hour12` setting of Settings → General: with AM/PM the
list reads "8:00 AM", "1:15 PM", ...; with 24 h "08:00", "13:15". The stored
value is always `HH:MM`; only the label changes. An error time is shown in the
same format.

## Migration on an existing master

The one shared report becomes the report of the **lowest-numbered admin** (the
first admin): on/off, recipients, day, time, language and last-sent date are
copied, so the weekly mail keeps going out, now from that admin's row. This
only happens if the master had such settings (`email_enabled` or `email_to`
present) and has at least one admin; otherwise no row is made. Other users
start without a report (off) and set their own on the Account page. The old
`email_%` keys are deleted afterwards, including the old last error (the first
admin gets a clean state). The SMTP file is unchanged.

## Tests

Master **381** tests (380 + 1 added during the mutation check), all passing;
`cargo fmt` and `cargo clippy` clean.

| Test | Area |
|------|------|
| `email::tests::every_user_gets_their_own_report_on_their_own_schedule` | two users, two schedules, one tick |
| `email::tests::monthly_means_the_first_of_the_month` | monthly only on day 1 |
| `email::tests::the_schedule_sends_once_on_the_day_and_retries_after_a_failure` | once per day, retry per user |
| `email::tests::a_refused_connection_is_an_error_that_is_kept_with_its_time` | error with time, cleared on success |
| `routes::email::tests::every_user_sets_their_own_report_on_the_account_page` | form, monthly option, only the sender shown, read-only users too |
| `routes::email::tests::the_time_follows_the_time_format_of_the_settings` | 24 h and AM/PM labels |
| `routes::email::tests::server_fields_sent_to_the_page_are_ignored` | no server through the form |
| `routes::email::tests::switched_on_it_needs_the_file_and_good_recipients_switched_off_anything_goes` | validation |
| `routes::email::tests::the_test_button_sends_your_own_report_and_shows_the_result` | test send |
| `routes::email::tests::admins_see_an_overview_of_every_users_report` | overview, read-only users refused, old routes gone |
| `routes::email::tests::saving_only_changes_the_report_of_the_logged_in_user` | **added after mutation 8**: logs in as a second user (id 2) |
| `db::tests::migration_12_gives_the_shared_report_to_the_first_admin` | migration with data |
| `db::tests::migration_12_without_a_report_makes_no_rows` | migration without data |

For the new test a test-only helper `logged_in_app_user(state, id, name, role)`
was added in `routes/login.rs` (inside `#[cfg(test)]`); `logged_in_app_as` now
calls it with id 1.

## Live check

Test master on `127.0.0.1:3078` with a fresh database: with AM/PM chosen on
General, the time list on the Account page shows "8:00 AM", "1:15 PM", ...; the
day list ends with "On the 1st of every month"; of the mail server only the
sender address shows. After saving monthly at 13:45, the admin overview showed
"On the 1st of every month, 1:45 PM" for admin.

## Mutation checks

Each deliberate bug applied, the whole `cargo test` run, files restored
afterwards (checked with `cmp`).

| # | Mutation | Result |
|---|----------|--------|
| 1 | `is_due`: "monthly" true every day | caught: `email::tests::monthly_means_the_first_of_the_month` |
| 2 | `tick` ignores `retry_at` | caught: `email::tests::the_schedule_sends_once_on_the_day_and_retries_after_a_failure` |
| 3 | `tick` uses one shared retry time (key 0) for all users | caught: `email::tests::the_schedule_sends_once_on_the_day_and_retries_after_a_failure` |
| 4 | `store_schedule` always stores for user 1 | caught: `email::tests::every_user_gets_their_own_report_on_their_own_schedule` |
| 5 | `time_choices` ignores `hour12` | caught: `routes::email::tests::the_time_follows_the_time_format_of_the_settings` |
| 6 | `record` keeps `last_error` on success | caught: `email::tests::the_schedule_sends_once_on_the_day_and_retries_after_a_failure` |
| 7 | migration 0012 uses `MAX(id)` instead of `MIN(id)` | caught: `db::tests::migration_12_gives_the_shared_report_to_the_first_admin` |
| 8 | `save` handler stores for user 1 instead of the current user | **survived at first** (`logged_in_app` always logs in as id 1); test `saving_only_changes_the_report_of_the_logged_in_user` added with a second session (id 2); re-run: caught |

7 of 8 caught at once; 1 survived and is caught after one extra test.
