# Change (0.4.0) — Scan now, new install link, `/healthz`, no double agents

**Repo:** `lunarscope-master` 0.4.0
**Date:** 2026-11-16
**Status:** Done — code, tests, mutation checks and an end-to-end test; not
committed yet

Four small points from the master review, built together.

## What changed

| Feature | Where | What it does |
|---------|-------|--------------|
| **Scan now** | Agents page, button per agent: `POST /agents/{id}/scan-now` | Raises the agent's `config_version`. At its next check-in (within 5 minutes) the agent sees a new version and scans at once, as after any configuration change. No new mechanism needed in the agent |
| **Scan all** | Agents page header: `POST /agents/scan-all` | The same for every agent |
| **New install link** | Agents page, per agent: `POST /agents/{id}/install-link` | A fresh one-time install command for an **existing** agent (1 hour, single use, only the SHA-256 of the token is stored). Running it gives the agent a **new API key**; the old key stops working. For a leaked key or a reinstalled server, without deleting the agent and its history |
| **`GET /healthz`** | No login | `200 {"status":"ok","version":"0.4.0"}`, or `503 {"status":"database unavailable"}` when SQLite doesn't answer. For monitoring and for `systemctl`/Caddy checks. Shows nothing else |
| **No double agents** | "Add agent" form | The form carries a hidden random `form_id` (64 hex). It is stored with the agent (`agents.form_nonce`, unique). Sending the same form again (double click, browser "resend") goes to that agent's card instead of adding a second agent. A POST without a valid `form_id` → 400 |

All four buttons are admin-only (see
[change-0.4.0-user-accounts.md](change-0.4.0-user-accounts.md)) and write
an audit line (`scan requested`, `install link made`, `agent added`).

## Code

| File | Change |
|------|--------|
| `migrations/0004_users_settings_updates.sql` | `agents.form_nonce` + unique partial index (`WHERE form_nonce IS NOT NULL`) |
| `src/db/queries.rs` | `request_scan(pool, Option<&str>)` (one agent or all), `add_install_token`, `agent_by_form_nonce`; `create_agent` stores the nonce |
| `src/routes/agents.rs` | `scan_now`, `scan_all`, `new_install_link`; `create_agent` checks `form_id` first; `NewAgentView.form_id` |
| `src/routes/api.rs` | `health` |
| `src/main.rs` | Four routes (`/healthz` outside the login) |
| `templates/agents.html`, `agent_new.html` | Buttons; hidden `form_id` |
| `scripts/demo-agents.sh` | Reads a fresh `form_id` from the form for every agent |

## Tests

| Test | Checks |
|------|--------|
| `the_same_form_sent_twice_adds_one_agent` | Second POST → 303 to the first agent's card; one agent |
| `form_without_id_is_refused` | 400 |
| `new_agent_form_has_a_fresh_id` | Two GETs give two different ids |
| `scan_now_raises_the_version_of_one_or_all_agents` | One agent → only its version +1; all → both +1; unknown agent → 404; both audit lines |
| `a_new_install_link_gives_an_existing_agent_a_new_key` | New link works once; the agent gets a new key and the old one is refused |
| `health_needs_no_login` | 200 with version without a cookie; 503 when the database is closed |

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| A double submit adds the agent again | `the_same_form_sent_twice_adds_one_agent` |
| "Scan now" for one agent scans all | `scan_now_raises_the_version_of_one_or_all_agents` |
| `/healthz` doesn't ask the database | `health_needs_no_login` |
| "Scan now" not written to the audit log | `scan_now_raises_the_version_of_one_or_all_agents` (after adding the audit check) |

4 of 4 caught; the last one only after the test also checked the audit log.

## End-to-end test

Temporary master on `127.0.0.1:3031` (release build, own database), one
`ubuntu:24.04` container `e2e-040`. The `lunarscope` service and the demo
containers were not touched.

| Step | Result |
|------|--------|
| `curl /healthz` without login | `{"status":"ok","version":"0.4.0"}` |
| "Add agent" form sent twice with the same `form_id` | First: install page. Second: `303 /agents#agent-d09093bb…`; one agent named `e2e-040` |
| POST without `form_id` | 400 |
| Agent installed and started | `scan cycle: 4 finding(s) …; accepted 4` |
| **Scan now** at 20:24:21 UTC | At the next check-in: `new configuration from the master (version 2), scanning now`, then a scan cycle (seen at 20:29:15, within the 5-minute poll) |
| **New install link** | Page with a fresh `/install/…` link; audit line `install link made` |
