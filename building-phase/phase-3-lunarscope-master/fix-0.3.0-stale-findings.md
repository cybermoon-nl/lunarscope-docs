# Fix (0.3.0) — fixed problems no longer stay on the dashboard

**Repos:** `lunarscope-agent`, `lunarscope-master` (part of the unreleased 0.3.0)
**Date:** 2026-11-16
**Status:** Done — code and checks ready; commit together with
[change-0.3.0-agent-management.md](change-0.3.0-agent-management.md)

## The problem

The master keeps the newest result of every check (`latest_results`) and
only replaces it when the same check is reported again. Some checks are
only reported while something is wrong:

- `ssh_scan` / `ssh_config_readable` ("Could not read /etc/ssh/sshd_config"),
  instead of the two real SSH checks,
- `package_scan` / `package_updates_checkable`, instead of the two update
  checks,
- a check removed from a rule scan, or a module's old check names.

After the problem was fixed the agent never sent that check again, so the
old warning stayed on the dashboard, in the counts and in the report
forever. It was point 1 of the master review ("still wrong").

The master couldn't tell on its own, because the agent sends every finding
as its own request and nothing marked the end of a scan.

## The fix

After a scan cycle whose findings all reached the master, the agent sends
one more request:

```http
POST /api/scan-complete
Authorization: Bearer lsk_…

{"agent_id": "…",
 "scans": [{"scan_type": "ssh_scan", "checks": ["ssh_permit_root_login", "ssh_password_authentication"]},
           {"scan_type": "package_scan", "checks": ["package_security_updates", "package_other_updates"]}]}
```

The master answers `{"removed": 1}` after it deleted, for every listed scan
type, that agent's latest results whose check isn't in the list. The
history in `scan_results` keeps everything.

Safety rules:

| Situation | What happens |
|-----------|--------------|
| Sending was aborted (network error, 401) | No scan-complete: the master would otherwise drop checks that just weren't sent |
| A finding was rejected (e.g. 400) but sending went on | Its check is still listed, so its old result stays |
| A module crashed (`<module>_crashed`) | That module isn't listed, so its old results stay |
| A module finished without findings | Listed with an empty list: all its old checks are removed |
| Scan types not listed (other modules, results of other agents) | Untouched |
| Old agent (doesn't send it) | Nothing changes, as before |
| New agent, old master (404) | Logged: "the master doesn't know /api/scan-complete (older than 0.3.0); fixed problems may stay on its dashboard" |

A removed check doesn't appear under "Resolved" in "Since previous scan":
that list shows checks whose severity changed, and this check is simply
gone.

## Code

| Repo | File | Change |
|------|------|--------|
| master | `src/routes/api.rs` | `POST /api/scan-complete` (`scan_complete`): API key of the agent, `agent_id` must match (401), at most 100 scan types and 1000 checks each, names 1–128 characters (400), body ≤ 64 KiB (413). Logs `agent …: removed N check(s) that are no longer reported` |
| master | `src/db/queries.rs` | `remove_missing_checks`: one transaction, `DELETE … WHERE agent_id = ? AND scan_type = ? AND check_name NOT IN (SELECT value FROM json_each(?))`; the list goes in as one JSON parameter, so names are data, never SQL |
| master | `src/main.rs` | Route with body limit |
| agent | `src/main.rs` | `scan()` also returns the modules that finished (didn't panic). `cycle()` sends scan-complete after the summary line when nothing was aborted, and logs `master removed N check(s) that are no longer reported` |
| agent | `src/sender.rs` | `CompletedScan`, `completed_scans()` (check names per finished module) and `Reporter::report_complete()` with clear errors |

## Tests

Master **221** (+6), agent **63** (+5).

| Test | Checks |
|------|--------|
| master `checks_not_reported_any_more_are_removed` | `ssh_config_readable` removed when the two SSH checks are listed; `package_scan` not listed → kept; history keeps all 4 rows |
| master `a_scan_with_no_checks_clears_that_scan_type` | Empty list removes all of that scan type |
| master `other_agents_are_not_touched` | Same scan type of another agent stays |
| master `needs_the_agents_own_key` | Another agent's key, or a wrong key → 401, nothing removed |
| master `bad_bodies_are_refused_and_remove_nothing` | Missing `scans`, empty scan type, too long name, 1001 checks → 400 |
| master `check_names_are_compared_exactly` | `a'b` kept, `%` not matched by `_` (no SQL, no patterns) |
| master `every_route_is_combined_in_app` | Route exists (401 without key) |
| agent `completed_scans_list_the_checks_per_finished_module` | Grouping per module; finished module without findings → empty list |
| agent `scan_complete_is_sent_with_the_key_and_the_checks` | Request line, `Authorization`, exact JSON body, `removed` read |
| agent `scan_complete_errors_are_explained` | 404 (old master), 500, invalid answer |
| agent `finished_cycle_ends_with_scan_complete` | A real `cycle()` against a fake master: 2 × scan-result, then scan-complete |
| agent `aborted_cycle_sends_no_scan_complete` | After a 401 only one scan-result, no scan-complete |
| agent `panicking_module_becomes_a_finding_and_others_still_run` (extended) | The crashed module is not in the finished list |

The fake master in the agent test records a request before answering it;
the first version did it after, which could make the test flaky (the agent
can have the answer before the test sees the request).

| Check | Agent | Master |
|-------|-------|--------|
| `cargo test --locked` | ✅ 63 | ✅ 221 |
| `cargo clippy --all-targets --all-features --locked -- -D warnings` | ✅ | ✅ |
| `cargo fmt --check` | ✅ | ✅ |
| `cargo build --release --locked` | ✅ | ✅ |

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| Master removes the *reported* checks instead (`IN` for `NOT IN`) | 4 tests |
| Master ignores the scan type | `checks_not_reported_any_more_are_removed` |
| Master ignores the agent | `other_agents_are_not_touched` |
| Master doesn't check `agent_id` against the key | `needs_the_agents_own_key` |
| Master doesn't check check names | `bad_bodies_are_refused_and_remove_nothing` |
| Agent sends scan-complete after an aborted cycle | `aborted_cycle_sends_no_scan_complete` |
| Agent doesn't list finished modules | 2 tests |
| Agent lists a crashed module as finished | `panicking_module_becomes_a_finding_and_others_still_run` |
| Agent mixes the checks of all modules | `completed_scans_list_the_checks_per_finished_module` |

All 9 caught.

## End-to-end test

Release builds, a temporary master on `127.0.0.1:3031` (own database and
password; the `lunarscope` service was not touched), one `ubuntu:24.04`
container `stale-test` added through "Add agent" with `ssh_scan` and
`package_scan`, installed with its install link:

1. Without SSH installed, `--once`:
   `ssh_scan/ssh_config_readable Low`, `package_security_updates High`,
   `package_other_updates Pass`.
2. `openssh-server` installed, `--once` again:

   ```text
   scan cycle: 4 finding(s) in 3430 ms; accepted 4, rejected 0, not sent 0
   master removed 1 check(s) that are no longer reported
   ```

   Latest results: `ssh_password_authentication Medium`,
   `ssh_permit_root_login Pass`, the two package checks;
   `ssh_config_readable` gone, still 1 row of it in the history. Master log:
   `agent 2669c301…: removed 1 check(s) that are no longer reported`.

(The order of the two agent log lines above is the final one; the first
build printed "removed" before the summary and was changed.)

## For the dev setup

Agents already installed run the old agent binary and don't send
scan-complete. After `cargo build --release` in both repos:
`sudo systemctl restart lunarscope` (copies the new builds) and run
`scripts/demo-agents.sh` again (the containers download the new agent).
