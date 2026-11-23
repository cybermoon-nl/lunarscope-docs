# Change (0.5.0) — UI feedback: Servers page, filters, Dutch first

**Repo:** `lunarscope-master` 0.5.0 (and the demo copy, via
`lunarscope-demo/sync-from-master.sh`)
**Date:** 2026-11-17
**Status:** Done — code, tests, mutation checks, checked in the browser on
the local demo; not committed yet

## The feedback, and what was done

| # | Feedback (user, in Dutch) | Done |
|---|---------------------------|------|
| 1 | New findings clickable, scroll down to them | Every item under "Since previous scan" (new and resolved) links to its row in the findings list (`#f-<agent>-<scan>-<check>`). Clicking scrolls the row to the middle, lights it up for 2 s and focuses it. If a filter hides the row, the dashboard opens without filters at that row |
| 2 | Rename the Agents tab to Servers | Sidebar, page title and buttons: "Servers", "Server toevoegen" / "Add server", "Server verwijderen" / "Remove server", "Terug naar servers". The URL stays `/agents` (install links and scripts use it) |
| 3 | Last check-in → last scan, plus the scan before it, for a time frame | Each card shows **Laatste scan** and **Vorige scan**: the end of the last two complete scans (`POST /api/scan-complete`). New columns `agents.last_scan_at`, `previous_scan_at` (migration `0005`); for existing agents the last scan is filled in from their newest result, the previous one after the next scan |
| 4 | "Server: hostname" on the Servers tab | Card heading `Server: web-01` |
| 5 | Enabled scans only as a list, with a "Change scans" button; there the scans with an explanation and a confirmation "do you really want to switch this on/off?" | The card shows the enabled scans as a list and a **Wijzig scans** button (admins). New page `GET /agents/{id}/scans`: every scan with its explanation (built-in scans have a longer explanation in NL and EN; rule scans keep their own description) and a switch. Every switch first asks e.g. "Wil je ssh_scan echt uitzetten voor web-01? De resultaten worden verborgen tot de scan weer aan staat." Read-only users can't open the page (403) |
| 6 | 24 hours by default, AM/PM in the settings | Settings → General: **Tijdnotatie** 24 hours (default) or 12 hours AM/PM. Applies to every time on the pages (`2026-11-17 2:30 PM CET`) and the scan time shown to read-only users. Saved in `settings.time_format`; audit line `time format set` |
| 7 | Saving the scan time: say it isn't saved yet | As soon as a scan time is changed: "Nog niet opgeslagen: klik op Opslaan." under the field, and the browser asks before leaving the page. After saving: "Scantijd opgeslagen." on that card |
| 8 | Findings per server on the Servers tab (a filter); filters on the home page are useful anyway | Each card has a fold-out **Openstaande bevindingen (n)** with that server's findings that didn't pass; "Bevindingen bekijken →" opens the dashboard filtered on that server. The dashboard got filters for **scan** (type), **zoeken** (check, description or server, any case, max 100 characters) and **verberg geslaagd**, next to severity and server, plus "Filters wissen". All filters stay in the URL and the 30 s refresh |
| 9 | Switches instead of ticks when installing an agent | "Server toevoegen" shows switches (checkboxes styled as switches, so the form and `demo-agents.sh` work as before) |
| 10 | Dutch by default, English second | Without a language cookie the pages are Dutch; the switch shows NL first |

Also fixed on the way:

- The scan time field was `type="time"`, which the browser shows in **its
  own** locale (an English browser showed `02:00 AM` even with 24 hours).
  It is now a text field `UU:MM` (24 hours, checked in the browser and on
  the server).
- "Laatst gezien" / "Laatste check-in" on the Servers page and "Laatste
  resultaat" on the dashboard were still in UTC instead of the chosen
  time zone.
- `demo-agents.sh` read the hostname from the card's `<h2>`; it now reads
  the card's `data-hostname`, because the heading says "Server: …".

## Code

| File | Change |
|------|--------|
| `migrations/0005_scan_moments.sql` | `last_scan_at`, `previous_scan_at` (+ fill-in), `time_format` setting |
| `src/db/queries.rs` | `Agent` has both moments; `record_scan()` |
| `src/routes/api.rs` | `scan_complete` calls `record_scan` |
| `src/routes/agents.rs` | Card: `last_scan`, `previous_scan`, `scans_on`, `findings`, `saved`, `scan_time_label`; `edit_scans` (new page); toggling goes back to that page; saving the time to `/agents?saved=<id>#agent-<id>` |
| `src/routes/dashboard.rs` | Filters `scan`, `q`, `hide_pass` (`matches()`), `filtered`, `scan_types` |
| `src/settings.rs`, `src/routes/settings.rs`, `src/time.rs`, `src/templates.rs` | `hour12`; `format_in_as`, `clock`; `Ui.hour12`, `ui.clock()` |
| `src/i18n.rs` | Dutch default; new texts; scan explanations |
| `src/routes/login.rs` | Read-only users can't open `/agents/{id}/scans`; test helper `english()` |
| `templates/agents.html`, `agent_scans.html` (new), `dashboard.html`, `findings_table.html`, `agent_new.html`, `settings.html`, `base.html`, `login.html` | The UI above |
| `static/app.js` | Jump to a finding; "not saved yet" + leave warning; confirmation already existed (`data-confirm`) |
| `scripts/demo-agents.sh` | `data-hostname` |
| `Cargo.toml` | 0.5.0 |

The existing tests check English texts; they now send the English language
cookie (`english()` around the test app). One new test checks that a page
without the cookie is Dutch with NL first.

## Tests

Master **284** (273 → 284).

| Test | Checks |
|------|--------|
| `without_a_language_cookie_the_pages_are_dutch_with_nl_first` | `<html lang="nl">`, Dutch label, NL before EN |
| `language_comes_from_the_cookie` (changed) | No or unknown cookie → Dutch |
| `agents_page_shows_a_card_per_agent` (changed) | `data-hostname`, "Server: web-01", enabled scans as list, "Change scans", no switches on the card, "not yet" |
| `cards_show_the_last_two_scans_and_the_open_findings` | Both scan moments in the chosen format; open findings without the passed one |
| `change_scans_page_explains_and_asks_before_switching` | Page, confirmation text with scan and server, explanations; 404 for an unknown agent |
| `read_only_users_cannot_open_change_scans` | 403; no button and no time field for read-only users |
| `scan_time_is_checked_and_saved` (extended) | Redirect with `saved`, "Scan time saved." only on that card |
| `switching_a_scan_raises_the_config_version` (changed) | Back to the Change scans page |
| `every_complete_scan_moves_last_to_previous` | Last → previous on every scan-complete; other agents and refused requests untouched |
| `findings_can_be_filtered_by_scan_search_and_passed`, `matches_scan_search_and_hide_pass` | New filters, kept in the refresh URL, unknown scan = all, search escaped and cut to 100 |
| `changes_link_to_their_row_in_the_list` | Link `#f-…` and the row's `id` |
| `twelve_hour_clock` | `00:05` → `12:05 AM`, `12:00` → `12:00 PM`, `2026-11-16 3:23 PM CET` |
| `time_format_is_24_hours_unless_am_pm_is_chosen` | Default 24h; 12h saved, in memory, on the page, in the audit log; old form = 24h |
| template tests | Every page (also `agent_scans.html`) renders in both languages; card and switch markup; texts from agents escaped |

`cargo clippy --all-targets --all-features -- -D warnings`, `cargo fmt
--check`: clean. `node --check static/app.js`: ok.

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| Read-only users may open Change scans | `read_only_users_cannot_open_change_scans` |
| Previous scan not kept | 2 tests |
| "Hide passed" ignored | 2 tests |
| Scan filter ignored | 2 tests |
| Passed checks shown as open findings | `cards_show_the_last_two_scans_and_the_open_findings` |
| Same question for switching on and off | `change_scans_page_explains_and_asks_before_switching` |
| "Saved" note on every card | `scan_time_is_checked_and_saved` |
| Time format not saved | `time_format_is_24_hours_unless_am_pm_is_chosen` |
| English the default again | 2 tests |

9 of 9 caught.

## Checked in the browser (local demo, `127.0.0.1:3040`, 4 demo servers)

| What | Result |
|------|--------|
| Login and pages without a cookie | Dutch ("Inloggen", "Servers", "Server toevoegen"), NL first |
| Servers page | `Server: demo-db-01`, Laatste scan `2026-11-17 09:43 UTC` (filled in by the migration), Vorige scan `nog niet`, scans as a list, Wijzig scans, Openstaande bevindingen 2/4/6/5 |
| Wijzig scans | 4 scans with explanation, switch "Aan", confirmation per scan with server name |
| Dashboard | Filters Ernst, Server, Scan, Zoeken, Verberg geslaagd; 17 clickable changes |
| Click on a new finding | Scrolled 0 → 913 px, row in the middle, lit up and focused |
| Same with `?severity=Pass` (row hidden) | Opened `/` without filters at the row, lit up |
| Scan time changed | "Nog niet opgeslagen: klik op Opslaan." appears; Save → "Scantijd opgeslagen." on that card only (set back to 02:00 afterwards) |
| Server toevoegen | 4 switches (34×20 px, green when on), built-in on, rule scan off |
| Time field | Showed `02:00 AM` with `type="time"` → replaced, now `02:00` |

## Addition: Europe/Amsterdam as the default time zone

Asked afterwards: "zet ook Europe/Amsterdam als default tijdzone".

- `settings::DEFAULT_TIMEZONE` = `Europe/Amsterdam`: used by
  `Settings::default()`, when the database has no time zone, and when the
  stored zone is unknown (was UTC in all three).
- Migration `0006_default_timezone_amsterdam.sql`: a stored `UTC` becomes
  `Europe/Amsterdam`, because until now UTC was only there as the default
  from migration 0004, not as a choice. Any other zone someone chose
  stays. Whoever really wants UTC chooses it again under Instellingen.
- Agents are unaffected in how they work: they still get UTC; a "Daily
  scan" of 02:00 now means 02:00 Dutch time (01:00 UTC in winter, 00:00 in
  summer). **On existing installs the daily scans therefore move one or two
  hours earlier**, at the next check-in.

Tests: **285**. New: `starts_in_amsterdam_and_keeps_a_saved_zone`,
`the_old_utc_default_becomes_amsterdam_but_a_chosen_zone_stays` (runs the
SQL of 0006 on a stored UTC, America/New_York, Europe/London, and no row),
`unknown_zone_in_the_database_falls_back_to_amsterdam`. Nine tests that
expected UTC times now expect the Dutch time (`CET`/`CEST`) or set UTC
themselves.

| Deliberate bug | Caught by |
|----------------|-----------|
| Default back to UTC | 10 tests |
| Migration also overwrites a chosen zone | `the_old_utc_default_becomes_amsterdam_but_a_chosen_zone_stays` |

Local demo after the restart: log `time zone Europe/Amsterdam` (its stored
`UTC` was converted).

## Second round of feedback (2026-11-17)

| # | Feedback | Done |
|---|----------|------|
| 1 | Make the tiles (Servers, Kritiek, Hoog, …) filters that apply right away | The six tiles are links: a severity tile filters the list on that severity (HTMX, URL updated) and keeps the other filters; the active tile is outlined and clicking it again, or the Servers tile, clears the severity. "In orde" leaves out "verberg geslaagd" (both together would show nothing) |
| 2 | The Change scans switch doesn't go to off | **Cause:** the confirmation used `window.confirm()`. The embedded browser in the Claude app (and some other browsers/settings) answers it with "no" at once without showing anything, so every confirmed form was cancelled silently — also "Server verwijderen" and "Nieuwe installatielink". **Fix:** an own dialog (`<dialog id="confirm-dialog">` in `base.html`, "Annuleren" / "Ja, doorgaan") for every `data-confirm` form; `window.confirm()` only as a fallback for browsers without `<dialog>` |
| 3 | "Bevindingen bekijken" from a server should also show only that server under "Sinds vorige scan" | With a server filter, "Sinds vorige scan" (and the scan/search filters) and the tiles only count that server |
| 4 | Overall risk score 18/100 while every server is above 60 — shouldn't it be the average? | **Cause:** the total subtracted the findings of **all** servers from 100 at once, so it kept dropping with every server added. **Fix:** the overall score is the average of the servers' scores (servers without results don't count; none → 100), rounded. Explanation text on the report updated |
| 5 | A save warning on the settings page | The settings form has the same "not saved yet" note as the scan time ("Gewijzigd maar nog niet opgeslagen: klik op Opslaan, anders gaat de wijziging verloren."), and leaving the page asks first. `app.js` now does this for every form with `data-unsaved` |

### Tests

Master **288** (+3, plus extended ones): `tiles_filter_on_their_severity_and_keep_the_other_filters`,
`a_server_filter_narrows_tiles_and_since_previous_scan`,
`overall_score_is_the_average_of_servers_with_results`, the report test now
expects 86 (average of 79 and 92) instead of 71, every page has the
confirm dialog, the settings form has `data-unsaved`.

| Deliberate bug | Caught by |
|----------------|-----------|
| Overall score from all findings again | `report_page_scores_servers_worst_first` |
| Servers without results count as 100 | `overall_score_is_the_average_of_servers_with_results` |
| "Since previous scan" ignores the server | `a_server_filter_narrows_tiles_and_since_previous_scan` |
| Tiles count all servers | same |
| The active tile doesn't clear its filter | 2 tests |
| The "In orde" tile keeps "hide passed" | `tiles_filter_on_their_severity_and_keep_the_other_filters` |

6 of 6 caught.

### Checked in the browser (local demo)

| What | Result |
|------|--------|
| `window.confirm()` in the embedded browser | Returned `false` without a dialog: the cause of the bug |
| Change scans → firewall_scan switch | Own dialog "Wil je firewall_scan echt uitzetten voor demo-web-01? …"; "Ja, doorgaan" → **Uit** (audit: `scan switched off`); again → question "aanzetten"; "Annuleren" → stays Uit; confirm → Aan |
| Dashboard `?server=<demo-web-01>` | Tiles Servers 1, Hoog 2 …; Sinds vorige scan: only demo-web-01 |
| Click the Hoog tile | URL `?severity=High&server=…`, tile marked, list 2 × Hoog |
| Report | Total **80** = average of 61, 79, 87, 91 (79.5); was 18 |
| Settings: choose AM/PM without saving | Note shown; left without saving, setting unchanged |

## Third round of feedback (2026-11-17)

| # | Feedback | Done |
|---|----------|------|
| 1 | Open findings on the Servers tab clickable | Each open finding on a card links to `/?server=<id>#f-<id>-<scan>-<check>`: the dashboard for that server, scrolled to that row, which lights up |
| 2 | The Servers tile clickable, with a popup to choose servers | The Servers tile opens a dialog "Welke servers?" with a switch per server, "Toepassen", "Alle servers" and "Annuleren". Chosen servers: tile shows "Servers · gefilterd" and the count; tiles, list and "Sinds vorige scan" follow them. The 30 s refresh waits while a dialog is open |
| 3 | Filters as "and/or": e.g. Kritiek **and** Hoog together | Severity and server take several values: `?severity=Critical,High&server=a1,a2` (the key may also be repeated, as the dialog's checkboxes send it; old one-value links still work). A severity tile adds its severity or takes it out again. The severity and server dropdowns in the filter bar are gone (tiles and dialog replace them); hidden fields keep them when scan, search or "verberg geslaagd" change. Unknown severities or servers are ignored |
| 4 | "Nu scannen" on the demo doesn't work | **Cause:** it worked, but invisibly: the button only raises the configuration version, and the agent asked for it only every **5 minutes**, so nothing happened for minutes and nothing said so (the audit log showed 6 presses in 3 s). **Fix:** (a) the card shows "Scan aangevraagd om 11:58 CET. Wacht op de agent …" until the next complete scan has arrived (new column `scan_requested_at`, migration `0007`; at most 15 minutes, for an agent that is offline), and the Servers page reloads itself every 10 s while a scan is pending (not while a scan time is being edited); (b) **agent 0.4.1** asks every **minute** instead of every 5 minutes. Texts "binnen 5 minuten" → "binnen een minuut" |

### Tests

Master **291**, agent **77**. New: `filters_take_several_severities_and_servers`
(parsing, order, dedup, `%2C`, `decode` with bad `%`/UTF-8),
`several_severities_and_servers_at_once` (Critical+High on two of three
servers, tiles and picker state, refresh URL, unknown servers, only-unknown
= all), `a_requested_scan_is_pending_until_a_scan_or_15_minutes`; extended:
tile toggling (add, remove, order), `scan_now_…` (pending note until the scan
arrives), the card's finding link, the picker in the page tests.

| Deliberate bug | Caught by |
|----------------|-----------|
| Severity filter ignored | 2 tests |
| Server filter ignored | 3 tests |
| A tile replaces the selection instead of adding to it | `tiles_filter_on_their_severity_and_keep_the_other_filters` |
| Unknown servers kept (`?server=zzz` would show nothing) | `several_severities_and_servers_at_once` (after adding the only-unknown case) |
| "Scan requested" stays after the scan came in | 2 tests |
| "Scan requested" stays forever | `a_requested_scan_is_pending_until_a_scan_or_15_minutes` |

### Checked on the local demo

The demo servers were reinstalled with agent 0.4.1 (`demo-agents.sh`,
which also showed the new `data-hostname` clean-up working).

| What | Result |
|------|--------|
| Nu scannen for demo-web-01 at 10:58:00 | Card: "Scan aangevraagd om 2026-11-17 11:58 CET …"; agent: `new configuration from the master (version 2), scanning now`; scan in at 10:58:52 (52 s); note gone |
| Servers tile | Dialog with 4 servers; demo-web-01 + demo-legacy-01 → tiles "Servers · gefilterd 2", only those two in the list |
| Kritiek, then Hoog | `?severity=Critical,High&server=…,…`, both tiles on, only Kritiek and Hoog of the two servers |
| Open finding on a card | Dashboard for that server, row in view and lit up |
| `app.js` | Served with `Cache-Control: no-cache`, so a new version reaches the browser at once |

## Fix: "Sinds vorige scan" follows the severity filter (2026-11-17)

Feedback: "de sinds vorige scan wordt niet geupdate met de filters van severity".

"Sinds vorige scan" followed the server, scan and search filters, but not the severity tiles. Now it follows all filters except "verberg geslaagd". A **new** change counts by its current severity; a **resolved** change is always Pass now, so it counts by the severity it **had** (`previous_severity`): with Hoog on, you see the High problems that were fixed.

Code: `dashboard::change_matches` takes the severity selection and whether the change is resolved.

Test: `since_previous_scan_follows_the_severity_filter` (a fixed High, a fixed Low, a new Critical and a new Medium: Critical+High shows 1 resolved and 1 new, Low shows only the fixed Low). Master **292** tests.

| Deliberate bug | Caught by |
|----------------|-----------|
| Changes ignore the severity filter | `since_previous_scan_follows_the_severity_filter` |
| A resolved change judged by its current Pass | same |

2 of 2 caught. Demo synced with `sync-from-master.sh` (292 tests on the copy) and restarted.

## Addition: understandable for people with little IT experience

**Why:** the user asked to make the dashboard understandable for non-technical people, so anyone with a little IT experience can use it.

### Plain words

| Before | Now |
|--------|-----|
| agent / check-in | server / last contact |
| Scan now | Check now (NL "Nu controleren") |
| Daily scan | Daily check at |
| Resolved / New | Fixed / New problems |
| Hide passed | Only show problems |
| Audit log | Activity log (NL "Logboek") |
| New install link | Reconnect server, with an explanation of when to use it |
| Risk score | Security score with a verdict (Good / Needs attention / Action needed) and "100 is the best" |

### Plain names and explanations

- Built-in scans get a plain name (`scanname_<scan>`): Remote login (SSH), Firewall, Software updates. Rule scans keep their own names (fallback via Tera `get(..., default=...)`; `i18n::scan_label()` in Rust for the switch confirmation).
- Each of the 7 built-in checks has a topic (`check_<check>`), why it matters (`why_<check>`) and what to do in plain words (`fix_<check>`).

### Pages

| Page | Change |
|------|--------|
| Findings table | Columns Severity / Server / Topic / What was checked / Checked. The agent ID column is gone. The agent's own English text is shown small under the plain topic. Rows carry `data-check` (tests find rows with it). |
| Details panel | "Why does this matter?", "What should you do?" (plain advice, nothing for a passed check, with "Not sure how? Send the technical details to whoever manages your servers") and a collapsed "Technical details (for your IT person)": result, technical fix, check name, server ID and times. |
| Dashboard | Each severity tile explains itself on hover (`sev_help_<severity>`, e.g. "High: real risk, fix this week") and there is a "What do the colours mean?" legend. With no servers, a 3-step "Get started" panel replaces the legend. |
| Add server | Help under the name and time fields. Scans are shown with plain name and explanation. The install page explains the steps (log in as administrator, paste, Enter; or send the command to whoever manages the server; then back to Servers). The technical explanation is collapsed. |
| Report | "Fix these first" shows the plain topic and plain advice, with the technical command small behind it. |

### Demo sync script

The i18n anchor of the demo patch in `sync-from-master.sh` moved from the `agent_updates` line (its text changed) to the `server_label` line.

### Tests

Master **293** passed, clippy and fmt clean.

- New: `built_in_scans_have_plain_names_and_their_checks_explanations` (every built-in check has `check_`/`why_`/`fix_` in both languages; a rule scan keeps its name).
- `finding_details_are_shown` checks plain names, `data-why`/`data-fix` and no advice for a passed check.
- `dashboard_shows_tiles_changes_filters_and_findings` checks the tile explanations and the legend.
- About 22 existing tests were updated to the new texts without weakening them.

| Deliberate bug | Caught by |
|----------------|-----------|
| U1: advice also shown for passed checks | `finding_details_are_shown` |
| U2: no plain scan names | `built_in_scans_…` and `change_scans_page_explains_and_asks_before_switching` |
| U3: table shows the agent's text instead of the plain topic | `finding_details_are_shown` |
| U4: no explanation on the tiles | `dashboard_shows_tiles_changes_filters_and_findings` |
| U5: an explanation missing for a check | `built_in_scans_…` |
| U6: report without plain advice | `report_shows_gauge_servers_and_actions` |

6 of 6 caught.

Demo synced with `sync-from-master.sh` (293 tests on the copy) and restarted on `127.0.0.1:3040`.

## Addition: plain texts for rule scans

### Why

The demo's rule scan showed the agent's English technical text ("Failed: telnetd is not installed … (telnetd is installed)") to readers. Rewriting only the description would not help: the agent adds "Failed:"/"OK:" and the reason itself, in English.

### What

- Rule scans get optional fields: `title` next to `name` (plain scan name), and per `[[check]]` a `title` (plain topic), `why` (why it matters) and `advice` (what to do).
- They can be in any language and are checked for length (4096) like the other texts. They are **not** sent to the agents (`skip_serializing`), so agents need no update.
- `rule_scans::plain_texts()` turns the stored TOML sources into the same keys the built-in scans use (`scanname_`, `check_`, `why_`, `fix_`).
- `AppState.rule_texts` keeps them in memory: read at startup, reread after a rule scan is saved or deleted.
- `templates::context` adds them to `t` but never replaces a built-in text.
- The editor shows a help line about the fields. The example (`nginx_scan`) uses them.

### Demo

`demo_baseline_scan` in `scripts/demo-agents.sh` now has Dutch plain texts: Basisbeveiliging; Wachtwoordbestand afgeschermd; Verouderd inlogprogramma (telnet) verwijderd; Schermen doorsturen via SSH uit.

### Tests

Master **297** passed, clippy and fmt clean.

- New: `plain_texts_are_read_from_the_sources_but_not_sent_to_agents`, `plain_texts_have_a_maximum_length`, `rule_scans_get_their_own_plain_texts_like_built_in_scans` (dashboard, before and after the texts are read), `rule_scan_texts_never_replace_built_in_texts`.
- `valid_scan_is_saved_and_can_be_edited_and_deleted` now checks the texts are used right after saving and gone after deleting.

| Deliberate bug | Caught by |
|----------------|-----------|
| R1: rule texts never used on pages | `rule_scans_get_their_own_…` and `valid_scan_is_saved_…` |
| R2: rule texts replace built-in texts | `rule_scan_texts_never_replace_built_in_texts` (the first version of the test let this survive; test added) |
| R3: no refresh after saving | `valid_scan_is_saved_…` |
| R4: no refresh after deleting | `valid_scan_is_saved_…` |
| R5: plain texts sent to agents | `plain_texts_are_read_…` |
| R6: no length limit | `plain_texts_have_a_maximum_length` |
| R7: blank texts used | `plain_texts_are_read_…` |

7 of 7 caught.

Demo synced with `sync-from-master.sh` (297 tests on the copy), restarted on `127.0.0.1:3040`, rule scan saved again over HTTP.

## Addition: a calmer look and a light theme

### Why

The user found the UI looked "AI-generated" and asked for a tighter look and a light mode. The design guidance came from the design-taste-frontend skill: one system, no violet, a sharp radius for developer tools, real hover and press states, reduced motion respected. Most of that skill is aimed at marketing websites (photos, hero sections) and does not apply to an admin dashboard, so only its system rules were used.

### What changed

All in `templates/base.html` (CSS) unless noted.

| Area | Change |
|------|--------|
| Colour | Violet/indigo accent (`#a5b4fc`) and the gradient moon logo removed. Neutral graphite palette. Flat, monochrome moon logo (also in `login.html`). Links and focus ring use one blue accent. |
| Badges | Severity badges are tinted chips with coloured text instead of solid pills. Server status labels too. Class names are unchanged. |
| Dashboard tiles | One joined strip instead of six cards with coloured left borders. A small colour square before the label. The active filter gets a 2px underline in its colour. |
| Shape | Smaller radius (6px / 4px). |
| Buttons | Primary button is ink-on-background (dark text on light, light text on dark). Buttons step on hover and move 1px when pressed. |
| Motion | Pulsing glow on the scan dot removed. `prefers-reduced-motion` turns transitions and animations off. |
| Report | Gauge track uses a token (class `gauge-track`) instead of a hard-coded colour. |

### Light theme

- All colours are CSS tokens on `:root`.
- Light values are under `:root[data-theme="light"]` and under `@media (prefers-color-scheme: light)` when no choice is saved. Without a choice the page follows the system.
- The sidebar button "Licht / donker" (i18n key `theme_toggle`, EN "Light / dark") flips the theme (`static/app.js`) and stores it in `localStorage` (`theme`).
- A small inline script in `<head>` applies the saved theme before the first paint, so there is no flash.
- The choice is not stored server-side: it is per browser.

### Tests

Master **297** passed, clippy `-D warnings` and fmt clean.

- No new Rust tests: the change is CSS and markup only, and existing tests still assert the markup (badge classes etc.).
- Mutation testing is not applicable to pure CSS.
- Checked visually in the browser in both themes on the demo (`127.0.0.1:3040`): dashboard, drawer, servers and report pages, at desktop and phone width.

### Follow-up: bigger, brighter severity colours

The user found the colours hard to see after the calmer restyle and asked for them bigger and brighter. Again only CSS in `templates/base.html`.

#### Brighter tokens

| Severity | Dark | Light |
|----------|------|-------|
| critical | `#ff5a5f` | `#d81e28` |
| high | `#ff8a2b` | `#d4540a` |
| medium | `#ffc53d` | `#a86f00` |
| low | `#38c0ff` | `#0a7cc4` |
| pass | `#3ddc84` | `#12895a` |

Low changed from grey-blue to sky blue so it stands out, but it still differs from the link/focus blue.

#### Bigger shapes

| Area | Change |
|------|--------|
| Badges and server status chips | Larger (13px / 12px, bold, more padding), stronger tint (20%) and a 1.5px border at 60% of the colour. |
| Dashboard tiles | Colour square 12px (was 7px). The number itself is in the severity colour again (30px). Active-filter underline 3px. |
| Server cards | Severity dots 11px, distribution bar 10px high. Scan status dot 10px. |

#### Tests

Master **297** passed. Checked in the browser in both themes.

### Follow-up: the Lunarscope logo and a favicon

The user supplied the real logo (a shield with a moon/keyhole shape) as `Logo-black.svg` and `Logo-white.svg`. Both have the same single path, only the fill differs.

#### Logo in the UI

The moon placeholder in the sidebar (`templates/base.html`) and on the login page (`templates/login.html`) is replaced by that path inline, with `fill="currentColor"`, 24px high. One copy therefore follows the light and dark theme automatically.

#### Favicon

| Item | Detail |
|------|--------|
| File | `static/favicon.svg`: the same path with a square viewBox. Embedded in the binary like `app.js`. |
| Route | `GET /static/favicon.svg` (`favicon()` in `src/routes/static_files.rs`), `Content-Type: image/svg+xml`, cached 1 day. Registered in `src/main.rs`. |
| Colour | Black by default, white when the browser itself is in dark mode (a `prefers-color-scheme` media query inside the SVG). |
| Head | Every page has `<link rel="icon" href="/static/favicon.svg" type="image/svg+xml">`. |
| Access | Reachable without logging in, so the login page has it too. |

#### Tests

Master **298** passed, clippy and fmt clean.

- New `favicon_is_served_as_svg`: 200, `image/svg+xml`, starts with `<svg`, contains the dark-mode query.
- The existing every-page head test now also asserts the icon link.
- The route table test lists `/static/favicon.svg`.
- Checked in the browser on the demo: logo in the sidebar and on the login page in both themes, and the favicon loads.

Later the user found the logo too small: it is now 36px high (was 24px), with the name beside it at 18px (was 15px), in the sidebar and on the login page. 298 tests still pass.

## Addition: problem titles, a score per server, copy buttons and English rule texts

### Why (user feedback)

1. A failed check showed its "good" title, e.g. Critical "Outdated login program (telnet) removed", which read as fine.
2. The report showed the average score (80) while one server was at 61. Three servers at 100 and one at 0 would still give 75.
3. The details panel said to send the details to your IT person but had no copy button. The details were folded away (also useful for people who manage their own server), and "Run:" was inside the fix box, so copying took the wrong text.
4. With EN selected much was still Dutch.

### 1. Problem titles

| Item | Detail |
|------|--------|
| New texts | `problem_<check>` for the 7 built-in checks, e.g. "Firewall is switched off" next to "Firewall switched on". |
| Rule scans | Get an optional `problem` field. |
| Choice | A failed check shows `problem_` (fallback `check_`), a passed one shows `check_`. |
| Used in | Findings table, changes list, server cards and the report. |
| Agent description | The agent's English description is no longer shown under the title in the table. It stays in the panel as "Result". |

### 2. A score per server in the report

- A circle per server (`templates/report_gauge.html`), worst first. Servers without results come last with "–".
- At most five circles; the rest are in a fold-out "Other servers, worst first".
- Each circle reads "Server: <name>" and links to `/?server=<id>` (the dashboard filtered on that server).
- The verdict now follows the weakest server (`weakest_score`, replaces `overall_score`).

### 3. Drawer: copy buttons

- Technical details are always visible.
- "Run: <command>" is split into a label "Run this command on the server:" above the box and only the command in the box, with a "Copy command" button.
- A "Copy details for your IT person" button copies finding, advice, command and all details as text.
- Copying falls back to a hidden textarea + `execCommand` when `navigator.clipboard` is not available (plain http on the network).
- A problem without plain advice says "See the technical details below." instead of the old misleading "Nothing: this is fine."

### 4. English rule texts

Cause: the i18n table was fine. The Dutch came from rule scan texts, which had one language.

- Rule scan title/problem/why/advice can now be one text or one per language: `title = { nl = "…", en = "…" }` (only `en` and `nl`; validated).
- Stored as `key@en` / `key@nl`. `templates::context` picks the page language first, then a language-neutral text, then another language.
- The demo rule scan (`scripts/demo-agents.sh`) now has nl and en texts.
- Without a language cookie the default is still Dutch (unchanged).

### Tests

- New: `verdict_follows_the_weakest_server_with_results`, `gauge_fills_its_share_of_the_circle`, `texts_can_be_given_per_language`, `rule_scan_texts_follow_the_page_language`, `report_shows_five_circles_and_folds_the_other_servers`.
- Updated: report, dashboard, server and template tests.
- 302 tests pass, clippy `-D warnings` and fmt clean.

### Mutation checks

| # | Mutation | Caught by |
|---|----------|-----------|
| M1 | Remove the problem title lookup in `findings_table.html` | `rule_scans_get_their_own_plain_texts_like_built_in_scans`, `finding_details_are_shown`, `every_file_in_templates_dir_is_embedded` |
| M2 | Verdict uses `.max()` instead of `.min()` (best server) | `verdict_follows_the_weakest_server_with_results`, `report_page_scores_servers_worst_first` |
| M3 | Wrong language picked first (`!=` instead of `==`) | `rule_scan_texts_follow_the_page_language` |
| M4 | Any language accepted in rule scan texts | `texts_can_be_given_per_language` |
| M5 | Gauge links to `/server/<id>` instead of `/?server=<id>` | `report_page_scores_servers_worst_first`, `every_file_in_templates_dir_is_embedded` |
| M6 | Fold limit 5 changed to 50 | `every_file_in_templates_dir_is_embedded`, `report_shows_five_circles_and_folds_the_other_servers` |
| M7 | "Run:" prefix left in the command box (`app.js`) | **Survived**: no Rust test covers the JavaScript, so it was only checked in the browser. |

### Follow-up: browser check

In the browser check, two built-in titles still read like problems on a passed check ("Logging in remotely as administrator (root)"). The `check_` texts of `ssh_permit_root_login` and `ssh_password_authentication` are now phrased as the good state: "No remote login as administrator (root)" / "Geen inloggen op afstand als beheerder (root)" and "No remote login with a password" / "Geen inloggen op afstand met een wachtwoord". The demo rule scan was re-saved over HTTP (`POST /scans`) so the running demo has the nl/en texts. Checked in the browser: EN dashboard fully English with problem titles; drawer shows the command label above the box with only the command in it (M7 checked by hand); "Copy details" shows "✓ Copied"; report circles link to the filtered dashboard.

### Follow-up: the browser's language when no language was chosen

The user agreed that a visitor who never pressed NL/EN gets the browser's language. `Lang::from_headers` works as follows:

1. The cookie comes first: a choice made with NL/EN always wins.
2. Otherwise `Accept-Language`: the highest-q of `en`/`nl` (no q = 1, a tie goes to the first, `en-GB` counts as `en`, q=0 means "not this one").
3. Otherwise Dutch, as before.

New test `without_a_choice_the_browser_language_is_used`. 303 tests pass, clippy and fmt clean.

#### Mutation checks

| # | Mutation (`src/i18n.rs`) | Result |
|---|--------------------------|--------|
| L1 | Browser language ignored (the `Accept-Language` fallback removed) | Caught by `without_a_choice_the_browser_language_is_used` |
| L2 | q=0 accepted (`weight > 0.0` check removed) | Caught by `without_a_choice_the_browser_language_is_used` |
| L3 | Tie goes to the last (`>=` instead of `>`) | Caught by `without_a_choice_the_browser_language_is_used` |
| L4 | Wrong default weight (0.5 instead of 1.0) | Caught by `without_a_choice_the_browser_language_is_used` |
| L5 | Case-sensitive language tag (no lowercase) | Caught by `without_a_choice_the_browser_language_is_used` |
| L6 | Browser beats the cookie choice | Caught by `without_a_choice_the_browser_language_is_used` |

All six mutations were caught; none survived.

### Follow-up: IP address, eight score circles and a dark mode switch

#### IP address

Requested "for speed" when fixing a problem.

- New migration `0008_agent_address.sql` adds `agents.last_address`.
- `GET /api/agent-config` records the address the master sees (`login::client_address`: the peer, or the last entry of `X-Forwarded-For` when the peer is this machine or a local proxy). A check-in without a known address keeps the previous one. No agent update is needed.
- The findings query carries it (`LatestFinding.address`, `FindingRow.address`).
- The details panel shows "<server> (<IP>)" just above the command box and an "IP address" row in the technical details ("Not known yet (shown after the next check-in)" when empty). "Copy details for your IT person" includes both.
- Behind NAT it is the address the master sees. The demo agents run with host networking, so they show 127.0.0.1.

#### Report: eight circles

- Up to eight circles in a row before the fold (was five).
- Circles are 92px (80px on phones), grid `auto-fill minmax(116px)` (100px under 800px), so narrower screens wrap to more rows instead of overflowing.
- Technical details become one column on phones.

#### Dark mode switch

- The theme button is now a switch (`role="switch"`, `aria-checked`, track + knob like the other switches) labelled "Dark mode" / "Donkere modus"; on = dark.
- It follows the system theme until switched, also when the system theme changes.
- The text is hidden on phones, the switch stays.

#### Tests

New `check_in_records_the_agent_address_for_the_findings`. The dashboard template test checks `data-address`, the schema test lists `last_address`, and the report fold test now uses 10 servers (8 + 2). 304 pass, clippy and fmt clean.

| # | Mutation | Caught by |
|---|----------|-----------|
| A1 | Findings query returns `NULL AS address` | `check_in_records_the_agent_address_for_the_findings` |
| A2 | Unknown address wipes the last one (`last_address = ?`) | `check_in_records_the_agent_address_for_the_findings` |
| A3 | Panel without address (`data-address=""`) | `dashboard_shows_tiles_changes_filters_and_findings`, `every_file_in_templates_dir_is_embedded` |
| A4 | Five circles instead of eight | `report_shows_eight_circles_and_folds_the_other_servers`, `every_file_in_templates_dir_is_embedded` |
| A5 | No fold (limit 80) | `report_shows_eight_circles_and_folds_the_other_servers`, `every_file_in_templates_dir_is_embedded` |

All five mutations were caught; none survived.

## Addition: PDF download of the report

### Why

The user wanted a download button on the report page that gives a PDF of the report: clear, but with everything in it.

### Approach

The PDF is generated on the master.

| Item | Detail |
|------|--------|
| Route | `GET /report.pdf`, behind the login like `/report`. |
| Headers | `Content-Type: application/pdf`, `Content-Disposition: attachment; filename="lunarscope-report-<date>.pdf"`, `Cache-Control: no-store`. |
| Dependency | `pdf-writer` 0.15.0 (typst's small low-level PDF writer; MIT/Apache-2.0). Chosen over `printpdf`, which pulls in many more dependencies, and over a headless browser, which would be an extra program on the server. |
| Fonts | The PDF standard fonts (Helvetica, Helvetica-Bold, Courier), so no font files are embedded. Text is converted to WinAnsi (Latin-1 plus typographic signs, otherwise "?"). Wrapping uses the fonts' published AFM widths. |
| Code | New module `src/report_pdf.rs`. In `routes/report.rs`, `load()` builds the `ReportView` for both the page and the PDF (it now also carries `others`, the Medium/Low problems, and the server address). `templates::text_map()` gives the same texts as the pages, including the rule-scan texts per language. |

### Contents (A4, light theme colours)

- Header with the shield logo (drawn from the SVG path), title, period and generation time.
- A summary box with the verdict (weakest server) and the explanation (without "click a circle").
- A totals strip per severity.
- A score circle per server (five per row, every server, with name and IP).
- The per-server table with IP.
- "Fix these first" (Critical/High): the plain problem title, server (IP), why, what to do and the technical fix. "Run:" becomes the label "Run this command on the server:" above a monospace box, and the label and box stay together on a page.
- "Other problems: plan these in" (Medium/Low), grouped per server with its score.
- "Generated by Lunarscope" and a footer "page n / N" on every page.

Long reports continue on new pages. The PDF is in the language of the user's interface.

### Button

"Download PDF" / "Download als PDF" next to the report title.

### Tests

- `report_pdf` tests: whole report present, page breaks with page numbers, empty report texts, WinAnsi, widths, wrapping (including cutting long paths), logo path parsing.
- Route test `report_pdf_is_a_download_with_every_open_problem`, the button on the report page, `/report.pdf` in the route table, and the login-redirect list.
- One existing test (agents card "Last check") depended on the date: 6 days later the value is also marked stale, so it now checks the date only.
- 312 pass, clippy `-D warnings` and fmt clean.

### Mutation checks

| # | Mutation | Caught by |
|---|----------|-----------|
| P1 | Passed checks included in the PDF (severity filter removed) | `report_pdf_is_a_download_with_every_open_problem` |
| P2 | Remediation text in the command box instead of only the command | `pdf_holds_the_whole_report` |
| P3 | Wrong page count (`total = 1`) | `long_reports_continue_on_new_pages_with_page_numbers`, `pdf_holds_the_whole_report`, `report_pdf_is_a_download_with_every_open_problem` |
| P4 | En dash written as a plain hyphen (encoding) | `text_is_written_in_win_ansi` |
| P5 | Lines allowed to be twice as wide | `wrapping_keeps_lines_within_the_width` |
| P6 | No address next to the server name | First **survived**. Then the assertion "legacy-01 (192.0.2.9)" (the server name with IP under each urgent problem) was added to `pdf_holds_the_whole_report`, and it is now caught by that test. |
| P7 | Button links to `/report` instead of `/report.pdf` | `report_page_scores_servers_worst_first`, `every_file_in_templates_dir_is_embedded` |
| P8 | `inline` instead of `attachment` | `report_pdf_is_a_download_with_every_open_problem` |

8 of 8 are caught. Pitfall: after a mutation restore, touch the file, or cargo may test a stale build.

### Visual check

Checked visually: a sample report (2 servers, urgent and other problems) rendered with `pdftoppm`. That showed two fixes, which were made:

- The summary box no longer repeats the section title and drops the "click a circle" sentence (new texts `pdf_summary` and `pdf_risk_explain`).
- The label and command box of a fix now stay on the same page.

Not yet checked with real data: the demo on 3040 was gone after the scratchpad was cleared, and the master on 3030 needs a new release build and a restart to get `/report.pdf`.

### Follow-up: theme setting and a PDF in the theme on screen

The user asked that the PDF is dark when the site is in dark mode, plus a setting in Instellingen: auto, light or dark.

#### Setting

- Settings, General: radio buttons Automatisch / Licht / Donker (texts `theme_label`, `theme_auto`, `theme_light`, `theme_dark`, `theme_help`).
- Stored in the settings table as key `theme` (no migration; default `auto`), kept in `AppState.settings` (`Settings.theme`), with the audit line "theme set". Unknown or missing values keep the current theme.
- Every page gets it as `<html data-theme-default>`. The inline head script uses the browser's own choice (the dark mode switch, localStorage) first, else this default; `auto` follows the computer.
- Saving the setting also clears this browser's own switch choice, so the new setting shows at once (`static/app.js`).
- Design choice: one default for everyone (set by an admin), with the switch as a per-browser override. The help text says so.

#### PDF in the theme

- Two palettes in `report_pdf.rs` (`Palette::LIGHT`, `Palette::DARK`, the dark theme's tokens). Every page is filled with the background colour and tints are mixed toward the background.
- The download button's link gets `?theme=light|dark` from the theme on screen (`app.js`, also after switching). Without the parameter, the setting decides; `auto` gives light, like paper.

#### Master on port 3030

- At the user's request the rule scan `demo_baseline_scan` was saved again via the logged-in browser (`POST /scans`), with the same checks plus the nl/en title/problem/why/advice texts from `scripts/demo-agents.sh`. Saving bumps the config version for agents using it. Before saving, the existing source was compared: the checks were identical. The dashboard on 3030 now shows e.g. "Outdated login program (telnet) is installed".
- IP addresses on 3030 are still empty, because the agents there have not checked in since 2026-11-16: their containers (web-01, db-01, legacy-01, dev-01) are stopped. An address is recorded at the next check-in (127.0.0.1 for these, which use the host network).

#### Tests

New `the_theme_setting_is_saved_and_given_to_every_page`, `the_dark_theme_has_dark_pages_and_its_own_colours`, `the_pdf_follows_the_theme_on_screen_or_the_setting`; html-tag assertions updated. 315 pass, clippy and fmt clean. The JS behaviour (head script, link, clearing on save) is checked in the browser, not by Rust tests.

| # | Mutation | Caught by |
|---|----------|-----------|
| T1 | Theme not saved (`before.theme` kept) | `the_theme_setting_is_saved_and_given_to_every_page` |
| T2 | Default not on the pages (`data-theme-default="auto"`) | `the_theme_setting_is_saved_and_given_to_every_page`, `every_file_in_templates_dir_is_embedded` |
| T3 | `?theme=dark` ignored | `the_pdf_follows_the_theme_on_screen_or_the_setting` |
| T4 | Setting ignored by the PDF | `the_pdf_follows_the_theme_on_screen_or_the_setting` |
| T5 | First page not dark | `the_dark_theme_has_dark_pages_and_its_own_colours`, `the_pdf_follows_the_theme_on_screen_or_the_setting` |
| T6 | Later pages not dark | `the_dark_theme_has_dark_pages_and_its_own_colours` |
| T7 | Theme lost after restart (always `auto`) | `the_theme_setting_is_saved_and_given_to_every_page` |

All seven mutations were caught; none survived.

### Follow-up: a setting for the PDF's theme

The user asked for a setting just for the PDF, light or dark.

- Settings, General, "PDF-rapport" / "PDF report": "Zoals het scherm bij het downloaden" (default, `screen`: the behaviour from the previous section), Licht, Donker.
- Stored as settings key `pdf_theme` (default `screen`), `Settings.pdf_theme`, audit line "PDF theme set". Unknown or missing values keep the current value.
- In `GET /report.pdf` the setting wins: light or dark always. Only `screen` uses `?theme=` from the button and then the theme setting.
- `settings.rs` got a small shared `save(key, value)`.
- Tests extended: `the_theme_setting_is_saved_and_given_to_every_page` (`pdf_theme` saved, shown, kept on unknown, after restart) and `the_pdf_follows_the_theme_on_screen_or_the_setting` (the setting wins over the screen). 315 pass, clippy and fmt clean.

| # | Mutation | Caught by |
|---|----------|-----------|
| Q1 | PDF "dark" setting ignored | `the_pdf_follows_the_theme_on_screen_or_the_setting` |
| Q2 | PDF "light" setting ignored | `the_pdf_follows_the_theme_on_screen_or_the_setting` |
| Q3 | `pdf_theme` not saved | `the_theme_setting_is_saved_and_given_to_every_page` |
| Q4 | `pdf_theme` lost after restart (always `screen`) | `the_theme_setting_is_saved_and_given_to_every_page` |
| Q5 | Chosen option not shown as checked | `the_theme_setting_is_saved_and_given_to_every_page`, `every_file_in_templates_dir_is_embedded` |

All five mutations were caught; none survived.
