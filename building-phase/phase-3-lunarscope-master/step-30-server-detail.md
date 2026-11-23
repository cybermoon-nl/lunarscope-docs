# Step 30 — Server detail route: `GET /server/{agent_id}`

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

> **Update 2026-11-09:** The server page uses the same stale rule as the dashboard, which is **25 h** since master v0.2.0 (it was 2 h). See [change-0.2.0-daily-scan-time.md](../phase-2-lunarscope-agent/change-0.2.0-daily-scan-time.md).

> **Update 2026-11-16:** Since master v0.2.0 this page needs a login, like the dashboard. See [change-0.2.0-dashboard-login.md](change-0.2.0-dashboard-login.md).

## Goal

Query all findings of one agent, sorted by severity, and render them in a
separate template.

## What was done

### Files

| File | Change |
|------|--------|
| `src/routes/server.rs` | New — handler `server`, 404 page, counts, 12 tests |
| `templates/server.html` | New — header (hostname, id, registered, last seen), counts, findings table |
| `templates/not_found.html` | New — 404 page in the dashboard layout |
| `src/db/queries.rs` | `agent_by_id()`, `latest_findings()` (sorted in SQL) |
| `src/templates.rs` | `ServerView`, `AgentInfo`, `FindingRow`, `NotFoundView`; 2 new tests |
| `src/routes/dashboard.rs` | `is_stale()` made a shared function (used by both pages) |
| `templates/base.html` | `td.text`: long description/remediation cells wrap |
| `src/main.rs` | Route `GET /server/{agent_id}` |

**axum 0.8 path syntax:** the route is written `/server/{agent_id}`. The
guide's `:agent_id` is the syntax of axum 0.7 and earlier; 0.8 panics at
startup on the old form.

### What the page shows

"All findings of one agent" is the **newest result of every check**, from
`latest_results` (step 29), not the complete history. With hourly scans the
history holds 5 rows per hour per agent (43,800 a year), and the same check
would appear thousands of times, mostly with the same result. The admin
wants to know what is wrong **now**, and each row says when that check last
ran ("Checked").

| Column | Source |
|--------|--------|
| Severity | badge, coloured, with the word |
| Module | `scan_type` |
| Check | `check_name` |
| Finding | `description` |
| Remediation | `remediation`, or "—" when there is none (Pass) |
| Checked | timestamp of that result, `YYYY-MM-DD HH:MM UTC` |

Above the table: hostname, agent id, registration time, last seen (red when
stale, same 2 h rule as the dashboard), and the number of checks per
severity.

### Sorting

In SQL, so the database does it with the rows it already has:

```sql
SELECT scan_type, check_name, severity, description, remediation, timestamp
FROM latest_results
WHERE agent_id = ?
ORDER BY CASE severity
             WHEN 'Critical' THEN 0 WHEN 'High' THEN 1 WHEN 'Medium' THEN 2
             WHEN 'Low' THEN 3 ELSE 4
         END,
         scan_type, check_name
```

Most severe first (as the architecture document 2.3 asks: "sorted by severity
(Critical → High → Medium → Low)"), then by module and check, so the order is
stable between page loads.

### Responses

| Situation | Answer |
|-----------|--------|
| Known agent | 200, HTML |
| Known agent, no results yet | 200, "This agent has not sent any results yet." |
| Unknown agent id | **404**, HTML page "This server is not registered." with a link back |
| Database error | 500 "internal server error" (logged) |

## Choices and justification

- **404 for an unknown agent**, not an empty 200 page. A mistyped or deleted
  agent id shouldn't look like a healthy server without findings. The 404 is
  a real page in the dashboard layout, with a way back.
- **Agent-supplied text is escaped** — `description`, `remediation`,
  `check_name` and `scan_type` all come from the agent. As on the dashboard
  (step 28), autoescaping turns them into text. The test
  `agent_data_is_html_escaped` sends `<script>`, `<img onerror>` and HTML tags
  in every field.
- **The id in the URL is only a bound parameter** (`WHERE id = ?`). URL tricks
  such as `' OR '1'='1`, `../`, or a NUL byte just look up an agent with that
  odd id, find none, and give 404.
- **Long text wraps** in the Finding and Remediation columns, while the short
  columns stay on one line. On a phone the table scrolls inside its box
  (step 28).

## Checks

### Unit tests (`src/routes/server.rs`)

Results are stored through the real `insert_scan_result()`.

| Test | Checks |
|------|--------|
| `unknown_agent_is_404_page` | 404, HTML, "This server is not registered.", title "Not found", link to `/` |
| `agent_without_results_shows_message` | 200, hostname as heading, "not sent any results yet", "last seen never", registration time |
| `findings_are_sorted_by_severity_then_module_and_check` | 6 checks inserted in random order appear as Critical, High (a), High (b), Medium, Low, Pass; counts per severity |
| `same_severity_is_sorted_by_module_first` | `a_scan/z_check` before `z_scan/a_check` |
| `only_the_newest_result_per_check_is_shown` | High then Pass for one check → only the Pass row, once |
| `other_agents_findings_are_not_shown` | Another agent's Critical check isn't on this page |
| `finding_details_are_shown` | Badge, module, description, remediation, "—" for none, checked time |
| `stale_agent_is_marked` | Last seen > 2 h → `<span class="stale">` |
| `agent_data_is_html_escaped` | `<script>`, `<img onerror>`, `<b>`, `<i>` in description/remediation/check/module are escaped |
| `dashboard_link_leads_to_the_detail_page` | The `href` taken from the rendered dashboard opens this page (200) |
| `path_tricks_do_not_reach_other_pages` | SQL-like id, `..%2F`, `%00` → 404; `/server/` → 404 |
| `database_failure_is_500` | Closed pool → 500 |

New in `src/templates.rs`:

| Test | Checks |
|------|--------|
| `detail_and_not_found_pages_extend_base` | Both pages start with the base layout, load HTMX, contain no template syntax |
| `every_file_in_templates_dir_is_embedded` | The files in `templates/` are exactly the embedded list |

**Why the last test was added.** While writing this step, adding the two
templates to the embedded list failed silently. `rustfmt` had split the
existing `dashboard.html` entry over several lines, so a text replacement
missed it. The code compiled and `all_templates_parse` passed, because it
only checks the templates that *are* in the list. Rendering then failed at
runtime with *"Template 'server.html' not found"*. The route tests caught it,
and the new test now catches a forgotten template directly.

Total master tests: **116**, all passing.

### Mutation checks

| Bug introduced | Failing tests |
|----------------|---------------|
| `server.html` not embedded | `every_file_in_templates_dir_is_embedded` + all detail-page tests that render it |
| no module/check order within a severity | `same_severity_is_sorted_by_module_first` |
| Critical sorted last | `findings_are_sorted_by_severity_then_module_and_check` |
| findings not filtered by agent (`OR 1`) | `other_agents_findings_are_not_shown` |
| full history (`scan_results`) instead of `latest_results` | `only_the_newest_result_per_check_is_shown` |
| unknown agent answered with 200 | `unknown_agent_is_404_page`, `path_tricks_do_not_reach_other_pages` |
| `{{ finding.description \| safe }}` | `agent_data_is_html_escaped` |

### Browser check

A detail page with the five real check names from `lunarscope-modules` and
the 404 page were rendered and opened in a browser
([server page](evidence/step-30-server-sample-render.html),
[404 page](evidence/step-30-not-found-sample-render.html)):

| Check | Result |
|-------|--------|
| Desktop (1200 px) | Header, counts, table; long remediation texts wrap |
| Order in the page | High `firewall_ufw_active`, High `package_security_updates`, Medium `ssh_password_authentication`, Pass `package_other_updates`, Pass `ssh_permit_root_login` |
| Phone (375 px) | Page doesn't scroll sideways; the table scrolls in its box |
| 404 page | Layout, message, link back |

```text
$ cargo test                                → 116 passed, 0 failed
$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

## Next step

Step 31 — HTMX refresh: `hx-get="/" hx-trigger="every 30s"` on the findings
block.
