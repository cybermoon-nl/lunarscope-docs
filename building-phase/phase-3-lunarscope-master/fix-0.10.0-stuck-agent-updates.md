# Fix (master 0.10.0, agent 0.5.2): an agent update that stays on "requested"

## Problem

On the demo server, Update was pressed for the agents. An hour later the
Lunarscope updates page still said "Update requested, at the next contact",
although the agents kept checking in every minute.

## Causes

1. **The demo got no new agent version.** In `lunarscope-agent` the version
   was raised to 0.5.2 at 14:01. But `lunarscope-demo/agent/Cargo.toml`
   still said 0.5.1: `sync-from-master.sh` had not copied it over. So the
   0.5.1 binary was signed again (`.sig` with `"version": "0.5.1"`) and
   uploaded. Signing does not check which version you meant.
2. **A failed update stayed silent and was never tried again.** This is
   the real bug, in agent ≤ 0.5.1 and master ≤ 0.9.0:
   - The agent only tries an offer it hasn't seen yet
     (`fetched.update != current.update`). If the download, the signature
     check or the key fails once, it writes one line in its own log and
     never tries that offer again until it restarts.
   - The master hears nothing about it, so the page shows "requested"
     forever.
   - Pressing Update again changes nothing, because the agent sees the
     same offer.
   - An agent with no update key built in (built while `update-key.pub`
     was still empty) can never update itself. The page did not say this
     either.

   The agents on the demo server show "requested", so they run an older
   version than the 0.5.1 on offer, or report no version at all.
   Something in that attempt failed. The page can't show why: the reason
   is only in the agent log in the container.

## Fix

### Master 0.10.0

- Migration `0013_update_progress.sql` adds these columns to `agents`:

  | Column | Meaning |
  |--------|---------|
  | `update_offered_at` | When the master first handed the offer over. |
  | `update_error`, `update_error_at` | The reason the agent gave and when. |

- **Pressing Update again makes every agent try again.** If the agent
  already got the offer, Update also raises its configuration version.
  After a new configuration, every agent (also 0.5.0 and 0.5.1) first
  tries the offer again and then scans. So the demo agents don't need a
  reinstall for this.
  - The first press changes no configuration.
  - Pressing several times before the next check-in counts once.
  - Tried first and rejected: holding the offer for one check-in. That
    doesn't work, because the agent ignores a configuration without an
    offer and so keeps seeing the "same" offer. The live test showed it:
    the agent did not try again.
- **New API: `POST /api/update-failed`** with body
  `{agent_id, version, error}`.
  - Authenticated with the agent's API key; the `agent_id` must be its own.
  - Control characters are removed and the stored text is cut at 500
    characters.
  - It is only stored while an update is requested.
  - It answers 204.
- **The Lunarscope updates page has two new statuses:**
  - **Update failed:** shows the reason the agent gave, with the time.
  - **Stuck:** the agent got the offer at least 3 minutes ago and still
    checks in with the old version. The page then says to look at the
    agent log. This covers agents that can't report yet (≤ 0.5.1).

  Both statuses get a **Try again** button. It starts over: offer
  time and error are cleared. When the agent runs the new version, all of
  it is cleared.

### Agent 0.5.2

- A failed update is reported to the master (`report_update_failed`), and
  so is the case where no key is built in.
- The same offer is tried again after 10 minutes
  (`UPDATE_RETRY_SECONDS = 600`). `compare()` takes a `retry_update`
  flag, and `wait_for_scan()` takes the time of the next try. Only an offer
  that is newer than the agent is tried again.

### Phones (all tables)

On screens up to 700 px wide, every dashboard table becomes a stack of
cards: findings, server detail, scans, users, activity log, report,
e-mail overview and updates.

- Each row is a card, and each cell is a line with its label on the left
  (`data-label` with the same i18n key as the column).
- Actions sit on their own line, and buttons are at least 40 px tall.
- Long names wrap.
- The fixed width of the findings table (1000 px) no longer applies on
  phones, so the page no longer scrolls sideways.
- Settings tabs scroll sideways inside their own bar.
- The scan status on the server page wraps; it was 703 px wide.
- Desktop is unchanged.

## Checks

| Check | Result |
|-------|--------|
| Master `cargo test` | 385/385 (was 381). New: `pressing_update_again_makes_an_agent_that_failed_see_a_new_offer`, `an_agent_can_report_why_the_update_failed`, `a_requested_update_that_does_not_happen_is_shown`, `the_page_shows_why_an_update_failed_with_a_retry_button`; columns test and templates test extended. |
| Agent `cargo test` | 78/78. New: `a_failed_update_is_tried_again_after_ten_minutes`; tests for no key and wrong signature now also expect `POST /api/update-failed`. |
| `cargo fmt --check`, `cargo clippy --all-targets --all-features -D warnings` (both) | clean |

Mutation checks (each change was made, the tests were run, and the change
was reverted):

| Mutation | Caught by |
|----------|-----------|
| Update never raises the configuration version | 1 test |
| Update always raises it (also the first time) | 2 tests |
| Stuck at `>` instead of `>=` 180 s | boundary test |
| Store the error even when nothing is requested | report test |
| Ignore the error in the status | 2 tests |
| Overwrite the first offer time on every check-in | retry test |
| Don't cut the error at 500 characters | report test |
| Agent: ignore the retry flag | retry test |
| Agent: don't report the failure | 2 tests. At first a test hung on `rx.recv()`; it now uses `recv_timeout(5 s)`. |
| Agent: retry at once instead of after 10 min | retry test |

Live test: a test master 0.10.0 on 127.0.0.1:3078 with a fresh database,
offering a binary "9.9.9" signed with a throwaway key, so the signature
does not match the built-in key.

| Agent | What happened |
|-------|---------------|
| 0.5.2 | It downloaded and refused the update, and reported it. The page showed "Update failed: 9.9.9: the signature doesn't match the built-in update key (time)", with Try again, on desktop and at 375 px. |
| 0.5.1 (the old demo binary) | It tried once and reported nothing. With the offer time put back 5 minutes, the page showed the stuck text (NL). After **Opnieuw proberen** the agent got configuration version 2, tried the update again within a minute, and then scanned. |

At 375 px the status cell first split into narrow columns. Its content is
now wrapped in one element.

## For the demo server

1. Synchronise first, and check that the demo really has the new version:
   ```bash
   cd lunarscope-demo && ./sync-from-master.sh && grep -m1 ^version agent/Cargo.toml
   ```
2. Build, sign and upload as before (`update-sign` now says `version
   0.5.2`), then run `setup-server.sh`.
   The demo is already synchronised: master 0.10.0, agent 0.5.2.
3. Press **Update all**. If it fails, the page now shows why ("Update
   failed: …"), or that the agent got stuck. You can see the old agents'
   own reason with:
   ```bash
   podman exec web-01 grep -i update /var/log/lunarscope-agent.log | tail
   ```
