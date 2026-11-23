# Tests — `lunarscope-agent`

**Last updated:** 2026-10-29 (step 21)

> **Update 2026-11-09:** This page describes v0.1.0 (33 tests). v0.1.1 added 2 tests ([fix-0.1.1-ca-certificates.md](fix-0.1.1-ca-certificates.md)). v0.2.0 replaced the interval tests with `scan_time` and schedule tests, for **42** in total, with 7 more mutation checks ([change-0.2.0-daily-scan-time.md](change-0.2.0-daily-scan-time.md)).

The agent is a binary crate. Its tests are `#[cfg(test)]` modules in each
source file: 12 in `config.rs`, 10 in `sender.rs`, 11 in
`main.rs`. Total **33**.

```bash
cargo test
```

## Approach

- **Pure functions where possible**: `Config::parse`, `parse_args`,
  `get_enabled_modules`, `scan`, `payload_json` take their input as arguments,
  so the tests don't need a real `/etc/lunarscope/config.toml`.
- **A real HTTP round trip without extra crates**: the sender tests start a
  tiny HTTP server on `127.0.0.1:0` (std `TcpListener` in a thread). It records
  each request (request line, headers, JSON body) and answers with a
  configured status. This tests the real reqwest client, headers and body,
  not a mock of it.
- **Test modules for edge cases**: `FixedModule` (two findings) and
  `PanickingModule` (always panics) implement `ScanModule` inside the tests.
- **Things unit tests can't cover were checked by hand and recorded as
  evidence**: the loop with a master outage, TLS behaviour, memory on
  Ubuntu, and the systemd service.

## Tests per step

| Step | Tests |
|------|-------|
| 11 — crate | build + `Cargo.lock` pinned to the `v0.1.0` commit (manual) |
| 12 — config | `parses_valid_config`, `missing_field_is_parse_error`, `unknown_field_is_parse_error`, `wrong_type_is_parse_error`, `negative_interval_is_parse_error`, `too_small_interval_is_rejected`, `empty_values_are_rejected`, `plain_http_only_allowed_for_localhost`, `bad_master_url_is_rejected`, `missing_file_is_read_error`, `load_reads_file_from_disk` |
| 13 — config.toml | `example_config_in_repo_is_valid` |
| 14 — registry | `enabled_modules_follow_config_order`, `all_three_modules_can_be_enabled`, `unknown_module_is_an_error`, `duplicate_module_runs_once` |
| 15 — scan | `scan_collects_findings_of_all_modules_with_scan_type`, `panicking_module_becomes_a_finding_and_others_still_run`, `scan_with_real_modules_tags_every_finding` |
| 16 — HTTP | `payload_matches_api_specification`, `payload_without_remediation_has_null`, `timestamp_is_current_unix_time`, `endpoint_is_built_from_base_url`, `sends_one_authenticated_post_per_finding`, `unauthorized_stops_the_cycle`, `other_error_status_skips_only_that_finding`, `unreachable_master_aborts_without_panicking`, `error_chain_includes_causes_once`, `empty_cycle_sends_nothing`; manual TLS checks |
| 17 — timer | `default_args`, `config_and_once_flags`, `bad_args_are_errors`; manual loop run |
| 18 — errors | covered by the step 12/15/16 tests + manual outage and startup-error runs |
| 19 — release | manual measurements on Ubuntu 24.04 |
| 20 — systemd | `systemd-analyze verify`/`security`; real systemd run |
| — | `hostname_is_never_empty` |

## Mutation checks

Each bug was put in on purpose, `cargo test` was run, and the change was
reverted:

| Bug introduced | Failing tests |
|----------------|---------------|
| `deny_unknown_fields` removed from `Config` | `unknown_field_is_parse_error` |
| plain http allowed for every host | `plain_http_only_allowed_for_localhost` |
| no minimum interval | `too_small_interval_is_rejected` |
| `Authorization` without `Bearer ` | `sends_one_authenticated_post_per_finding` |
| 401 doesn't stop the cycle | `unauthorized_stops_the_cycle` |
| `#[serde(flatten)]` removed | `payload_matches_api_specification`, `payload_without_remediation_has_null`, `sends_one_authenticated_post_per_finding` |
| timestamp in milliseconds | `timestamp_is_current_unix_time` |
| no `catch_unwind` around `module.run()` | `panicking_module_becomes_a_finding_and_others_still_run` |
| unknown module names ignored | `unknown_module_is_an_error` |

## Result

```text
$ cargo test --locked
     Running unittests src/main.rs
test result: ok. 33 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

$ cargo clippy --all-targets --locked -- -D warnings   → no warnings
$ cargo fmt --check                                    → no changes
```
