# Change (0.4.0) — user accounts, read-only role and audit log

**Repo:** `lunarscope-master` 0.4.0
**Date:** 2026-11-16
**Status:** Done — code, tests, mutation checks and an end-to-end test; not
committed yet

## Why

Since 0.2.0 the dashboard had one shared password. Everyone who logged in
could change everything, and nothing recorded who did what. The user chose
**"Admin + read-only"**: named users with one of two roles, plus an audit
log.

## What it does

### Logging in

The login page asks for a **user name** and password. A wrong name and a
wrong password get the same answer ("Wrong user name or password.") and
take the same time: for an unknown name the password is still checked
against a dummy Argon2 hash, so timing doesn't reveal which names exist.
The lockout (5 failures within a minute, for everyone) and the 12-hour
sessions stay as in 0.2.0. A session now belongs to a user.

### Roles

| | Admin | Read-only (`viewer`) |
|---|---|---|
| Dashboard, server pages, Agents, Scans, Report | ✅ | ✅ (look only) |
| Buttons that change something (switch scans, scan time, Scan now, Add/delete agent, install links, rule scans) | ✅ | hidden |
| Settings (General, Users, Agent updates, Audit log) | ✅ | hidden, 403 |
| Any POST | ✅ | **403** |

Hiding the buttons is only for clarity. The real check is in
`require_login`: a read-only user may only send `GET` requests, and not to
`/settings…`, `/agents/new` or `/scans/…` (the editor). Anything else gets a
403 page "Only admins can do this. Your account is read-only."

The sidebar shows who is logged in and their role.

### Managing users (Settings → Users)

- Add a user: name (letters, digits, `.`, `_`, `-`, at most 64), password
  (at least 12 characters, Argon2id), role.
- Set a new password for any user: that user's sessions end at once.
- Delete a user: their sessions end at once. You can't delete **yourself**,
  and the **last admin** can't be deleted (nobody could manage the master
  then; checked inside one database transaction).

### The first admin

On a fresh database (no users yet) there are two ways:

- `--password-file` (as in 0.2.0): at startup the master makes user
  **`admin`** with that hash. Existing installs keep working: log in as
  `admin` with the old dashboard password. This only happens while the
  `users` table is **empty**.
- `lunarscope-master add-user <name> [--viewer] [--db <path>]`: asks for the
  password twice (or reads two lines from stdin) and adds the user, also
  while the master runs.

Without any user the login page says so and shows the `add-user` command
instead of a form.

### Audit log (Settings → Audit log)

The newest 200 lines, newest first, times in the chosen time zone:

| Action | When |
|--------|------|
| `logged in` / `login failed` / `logged out` | Login page (failed: with the name that was tried) |
| `agent added`, `agent deleted`, `scan switched on/off`, `scan time set`, `scan requested`, `install link made` | Agents page |
| `rule scan saved`, `rule scan deleted` | Scans |
| `time zone set`, `user added`, `user deleted`, `password changed`, `update requested` | Settings |

Each line has time, user, action and detail (e.g. which agent). Lines are
written with `?` parameters and shown escaped. The log is never cleaned up
by the maintenance task.

## Code

| File | Change |
|------|--------|
| `migrations/0004_users_settings_updates.sql` | `users(id, username UNIQUE, password_hash, role CHECK IN ('admin','viewer'), created_at)`, `audit_log(id, at, username, action, detail)` |
| `src/db/users.rs` (new) | `is_valid_username`, `user_count`, `user_by_name`, `users`, `create_user` (`ON CONFLICT DO NOTHING`), `delete_user` → `Deleted / NotFound / LastAdmin`, `set_password`, `add_audit`, `audit_log` |
| `src/session.rs` | `Role`, `User`, `CURRENT_USER` (Tokio task-local: the handler knows who is logged in without passing it around), `Login {sessions, limiter, verify_lock}`, `check_password` (dummy hash for unknown users), `Sessions` keep `(expiry, User)`, `remove_user` |
| `src/routes/login.rs` | Username field; `require_login` sets `CURRENT_USER` and enforces the read-only rule (`viewer_may`); audit lines |
| `src/audit.rs` (new) | `log(state, action, detail)` with the current user (or `system`) |
| `src/routes/users.rs` (new) + `templates/users.html`, `audit.html` | Users and Audit log pages |
| `src/templates.rs` | `Ui.user`; templates get `current_user`, `current_role`, `is_admin` |
| `src/main.rs` | `add-user` command, `bootstrap_admin`, startup line `dashboard has N user(s)`, routes |
| All templates | Admin-only controls inside `{% if is_admin %}` |
| `scripts/demo-agents.sh` | Logs in as `LUNARSCOPE_USER` (default `admin`) |

## Tests

| Test | Checks |
|------|--------|
| `users_are_created_found_and_listed`, `roles_are_checked_by_the_database`, `user_names` | Storage; names case-sensitive and unique; `root` refused by the CHECK |
| `the_last_admin_cannot_be_deleted`, `password_can_be_changed`, `audit_log_is_newest_first` | Database rules |
| `login_checks_the_password`, `session_holds_its_user_until_it_expires`, `removing_a_user_ends_all_its_sessions`, `roles_by_name` | `session.rs` |
| `without_users_the_login_page_explains_add_user` | No form, `add-user` hint |
| `unknown_user_gets_the_same_answer_as_a_wrong_password` | Same status and text, name kept in the field |
| `read_only_user_can_look_but_not_change` | Viewer: pages 200, POSTs and Settings 403, no admin buttons in the HTML |
| `admin_sees_the_controls_and_settings` | Admin: buttons and Settings link |
| `users_can_be_added_and_deleted_but_not_the_last_admin_or_yourself` | Validation messages, duplicate name, delete yourself refused |
| `a_deleted_user_is_logged_out_at_once` | The deleted user's cookie no longer opens the dashboard |
| `a_new_password_ends_that_users_sessions` | Old session redirected to login |
| `changes_and_logins_are_in_the_audit_log` | Lines for login and a change, with user |
| `read_only_users_cannot_see_or_press_update` | Agent updates tab |
| earlier login tests (cookie flags, lockout, logout, forged cookies) | Reworked for user names |

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| Read-only users may POST | `read_only_user_can_look_but_not_change` |
| Read-only users may open Settings | 2 tests |
| Roles not checked at all | 2 tests |
| The last admin can be deleted | `the_last_admin_cannot_be_deleted` |
| You can delete yourself | `users_can_be_added_and_deleted_but_not_the_last_admin_or_yourself` |
| A password change keeps the old sessions | `a_new_password_ends_that_users_sessions` |
| A deleted user keeps their sessions | `a_deleted_user_is_logged_out_at_once` (test added after this mutation first got through) |

7 of 7 caught.

## End-to-end test

Temporary master with an admin and a viewer (`add-user anne --viewer`):

| Step | Result |
|------|--------|
| Viewer `GET /` | 200, 0 admin buttons on the Agents page |
| Viewer `GET /settings`, `GET /agents/new`, `POST /agents/scan-all` | 403, 403, 403 |
| Wrong password for `anne` | No cookie |
| Admin: Agents page | Scan all button present |
| Audit log after the test | `logged in`, `login failed`, `time zone set`, `agent added`, `scan requested`, `install link made` with user names, in CET |

Found during this test (works as designed, now in the docs above): `anne`
was added with `add-user` **before** the first start, so the users table
wasn't empty and `--password-file` did not create `admin`. The admin was
then added with `add-user gijs`.

## For the dev service

After `sudo systemctl restart lunarscope` with this build, log in as user
**`admin`** with the existing dashboard password. Add your own accounts
under Settings → Users.
