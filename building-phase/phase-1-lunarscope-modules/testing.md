# Unit tests — `lunarscope-modules`

**Last updated:** 2026-10-17 (after step 10 + tests for steps 1–4)

Each module gets its unit tests in a `#[cfg(test)] mod tests` block in the
same file as the module (Rust convention; it also lets tests call the private
helper functions). Step 9 of the guide is about unit tests. To catch mistakes
early, they are now written together with each module, and step 9 will check
that every module is covered.

Run with:

```bash
cargo test
```

## Test approach

- **Logic is split from system access.** Each module has a small `run()` that
  reads the system (file, command), and pure functions that take that data
  as input (`scan_config(path)`, `evaluate(state, conf)`). Tests call the
  pure functions with controlled input, so every outcome can be tested on
  any machine.
- **One test per module runs the real `run()`.** The result depends on the
  machine, so these tests only check the shape: the expected `check_name`
  values, a filled-in description, and that `run()` never panics.
- **No extra test dependencies.** `ssh_scan` tests use a small `TempConfig`
  helper that writes config files to a unique directory under the system
  temp dir and removes it on `Drop`. This avoids adding `tempfile` (and its
  dependency tree) to the `cargo deny` licence check in step 37.

## Shared rules for every finding (step 9)

`assert_valid_finding(finding, known_checks)` in `src/lib.rs` (test-only) is
used by every module. It checks:

1. `check_name` is one of the module's known checks;
2. `description` is not empty;
3. `severity` serialises to `Critical`/`High`/`Medium`/`Low`/`Pass`;
4. `remediation` is set (non-empty) for every non-Pass finding and `None` for Pass.

Each module has an `all_outcomes_are_valid_findings` test (every possible
outcome through the helper) and a `run_returns_valid_findings` test (real
`run()` through the helper).

## Tests per file

### Tests per step

| Step | Where | Tests |
|------|-------|-------|
| 1 — crate setup | — | Configuration checks (`cargo metadata`, `cargo tree`, `git check-ignore`), see step 1 doc |
| 2 — `Severity` | `src/lib.rs` | `severity_serialises_as_variant_name`, `severity_debug_output_is_variant_name`, `shared_types_are_send_and_sync` |
| 3 — `Finding` | `src/lib.rs`, `tests/` | `finding_serialises_with_all_fields`, `finding_with_remediation_serialises_it_as_string`, `cloned_finding_is_independent`, `shared_types_are_send_and_sync`, `shared_types_are_usable_from_outside` |
| 4 — `ScanModule` | `src/lib.rs`, `tests/` | `scan_module_trait_objects_are_send_and_sync`, `modules_are_moved_and_shared_between_threads`, `findings_can_be_sent_back_from_a_thread`, `external_module_works_next_to_built_in_modules` |
| 5 — `ssh_scan` | `ssh_scan.rs` | 17 tests, see below |
| 6 — `firewall_scan` | `firewall_scan.rs` | 9 tests, see below |
| 7 — `package_scan` | `package_scan.rs` | 13 tests, see below |
| 8 — exports | `mod.rs`, `tests/` | `all_modules_have_unique_names`, `module_structs_are_exported_at_crate_root_and_in_modules`, `modules_can_be_filtered_on_config_names`, `every_module_runs_and_serialises` |
| 9 — shared rules | all modules | `assert_valid_finding` via `all_outcomes_are_valid_findings` + `run_returns_valid_findings` per module |

### `src/lib.rs` — shared types and trait

| Test | Checks |
|------|--------|
| `severity_serialises_as_variant_name` | JSON is `["Critical","High","Medium","Low","Pass"]` — the strings the master stores |
| `severity_debug_output_is_variant_name` | `{:?}` prints the variant name; `Clone` works |
| `finding_serialises_with_all_fields` | Exactly the four fields; `remediation: None` becomes `null` |
| `finding_with_remediation_serialises_it_as_string` | `Some(..)` remediation becomes a JSON string |
| `cloned_finding_is_independent` | `Clone` is a deep copy |
| `scan_module_trait_objects_are_send_and_sync` | Compile-time: `dyn ScanModule`, `Box<..>`, `Vec<Box<..>>` are `Send + Sync` |
| `shared_types_are_send_and_sync` | Compile-time: `Severity`, `Finding`, `Vec<Finding>` are `Send + Sync` |

### `src/modules/ssh_scan.rs`

| Test | Checks |
|------|--------|
| `name_matches_config_key` | `name()` is `"ssh_scan"` (must match `config.toml`) |
| `empty_config_uses_sshd_defaults` | Defaults: root login Pass (`prohibit-password`), password auth Medium (`yes`) |
| `hardened_config_passes` | Both `no` → both Pass, no remediation |
| `root_login_with_password_is_high` | `PermitRootLogin yes` → High with remediation |
| `key_only_root_login_values_pass` | `prohibit-password`, `without-password`, `forced-commands-only` → Pass |
| `password_authentication_yes_is_medium` | `PasswordAuthentication yes` → Medium |
| `first_value_wins` | Repeated keyword uses the first value (sshd rule) |
| `keywords_are_case_insensitive_and_accept_equals` | `permitrootlogin=no`, upper-case keyword, comments and blank lines |
| `match_block_does_not_change_global_setting` | Settings inside `Match` are ignored |
| `included_drop_in_takes_precedence` | Ubuntu layout: `50-cloud-init.conf` overrides the main file; non-`.conf` files ignored |
| `include_files_are_read_in_lexical_order` | `10-a.conf` is applied before `20-b.conf` |
| `expand_include_returns_sorted_matches_only` | Wildcard expansion returns only matching files, sorted |
| `relative_include_without_wildcard` | `Include extra.conf` is resolved relative to the config directory |
| `missing_include_directory_is_ignored` | Include pointing at a missing directory doesn't break the scan |
| `unreadable_config_gives_single_low_finding` | Missing main config → one `ssh_config_readable` Low finding |
| `all_outcomes_are_valid_findings` | Every outcome (5 configs + missing file) follows the shared rules |
| `run_returns_valid_findings` | Real `run()` returns `Vec<Finding>` following the shared rules |

### `src/modules/firewall_scan.rs`

| Test | Checks |
|------|--------|
| `name_matches_config_key` | `name()` is `"firewall_scan"` |
| `active_service_passes` | `active` + `ENABLED=yes` → Pass, no remediation |
| `active_service_without_readable_conf_passes` | `active` + unreadable `ufw.conf` → Pass |
| `active_service_with_disabled_conf_is_high` | `active` + `ENABLED=no` → High |
| `inactive_or_missing_service_is_high` | `inactive`, `failed`, `unknown`, `activating` → High, state in description, remediation allows SSH first |
| `systemctl_error_is_low` | systemctl can't run → Low with the error in the description |
| `conf_enabled_parsing` | `yes`/`"yes"`/`YES`, `no`, commented lines, missing key |
| `all_outcomes_are_valid_findings` | All 6 state/conf combinations follow the shared rules |
| `run_returns_one_valid_finding` | Real `run()` returns exactly one finding following the shared rules |

### `src/modules/package_scan.rs`

Uses a sample `apt-get -s upgrade` output (`SAMPLE`) in the Ubuntu 24.04
format: simulation notice, kept-back list, 3 security + 1 regular `Inst`
line, and the matching `Conf` lines.

| Test | Checks |
|------|--------|
| `name_matches_config_key` | `name()` is `"package_scan"` |
| `parses_only_inst_lines` | Exactly the 4 `Inst` packages are parsed, with the right category; `Conf` lines are ignored |
| `real_ubuntu_output_is_categorised` | Real `apt-get -s upgrade` output captured in an Ubuntu 24.04 container (interleaved `Inst`/`Conf`): 2 security (High) + 1 regular (Low), exact descriptions |
| `security_pocket_variants_are_security` | Ubuntu `noble-security`, Debian `stable-security`, ESM `noble-apps-security` → security; `-updates`, `-backports` → regular |
| `security_in_package_name_is_not_a_security_update` | `python3-security-tools` from `noble-updates` is regular |
| `pending_updates_give_one_finding_per_category` | Security → High with count and names; regular → Low; both with remediation |
| `kept_back_packages_are_not_counted` | Kept-back `linux-generic` does not appear in any finding |
| `up_to_date_system_passes_both_categories` | No `Inst` lines → two Pass findings without remediation |
| `long_package_lists_are_truncated` | 25 packages → count 25, first 10 names, `and 15 more` |
| `exactly_max_listed_has_no_more_suffix` | Exactly 10 packages → no `and N more` |
| `apt_error_gives_single_low_finding` | apt can't run → one `package_updates_checkable` Low finding |
| `all_outcomes_are_valid_findings` | Sample, real Ubuntu, up to date, empty output and apt error all follow the shared rules |
| `run_returns_valid_findings` | Real `run()` returns `Vec<Finding>` following the shared rules |

### `src/modules/mod.rs`

| Test | Checks |
|------|--------|
| `all_modules_have_unique_names` | The registry contains exactly `firewall_scan`, `package_scan`, `ssh_scan` |

### `tests/public_api.rs` — integration tests (step 8, extended after step 10)

Compiled as a separate crate, so they only see the public API, like the agent.

| Test | Checks |
|------|--------|
| `module_structs_are_exported_at_crate_root_and_in_modules` | Short (`lunarscope_modules::SshScan`) and full paths both work |
| `modules_can_be_filtered_on_config_names` | Filtering `all_modules()` on config names, as `get_enabled_modules()` will do |
| `every_module_runs_and_serialises` | All modules return ≥ 1 finding and serialise with all four JSON fields (renamed; see note in step 8) |
| `modules_are_moved_and_shared_between_threads` | `Arc<Vec<Box<dyn ScanModule>>>` shared by 4 threads running at the same time; all return the same checks |
| `findings_can_be_sent_back_from_a_thread` | A boxed module moved into a thread returns its findings to the caller |
| `external_module_works_next_to_built_in_modules` | A `DummyScan` defined outside the library implements the trait and runs next to `firewall_scan` after config-style filtering |
| `shared_types_are_usable_from_outside` | `Finding`/`Severity` construct, clone and debug-print from outside the crate |

## Do the tests actually catch bugs?

To check that the tests are not just passing trivially, deliberate bugs were
introduced one at a time (mutation testing by hand) and reverted afterwards:

| Bug introduced | Failing tests |
|----------------|---------------|
| `lookup` returns the **last** value (`rfind`) | `first_value_wins`, `included_drop_in_takes_precedence`, `include_files_are_read_in_lexical_order` |
| `Match` lines ignored instead of stopping | `match_block_does_not_change_global_setting` |
| Include matches not sorted | at first **none** — `include_files_are_read_in_lexical_order` passed by luck because the filesystem returned the files in sorted order. Added `expand_include_returns_sorted_matches_only` (5 files, created out of order), which now fails |
| `ufw.conf` `ENABLED=no` ignored | `active_service_with_disabled_conf_is_high` |
| package_scan: whole line searched for `-security` | `security_in_package_name_is_not_a_security_update` |
| package_scan: `Conf` lines also counted | `parses_only_inst_lines`, `pending_updates_give_one_finding_per_category` |
| package_scan: name list not truncated | `long_package_lists_are_truncated` |
| package_scan: every update treated as security | `pending_updates_give_one_finding_per_category`, `long_package_lists_are_truncated` |
| `PackageScan` missing from `all_modules()` | `all_modules_have_unique_names` |
| ssh Medium finding without remediation | `all_outcomes_are_valid_findings`, `password_authentication_yes_is_medium` |
| firewall Pass finding with a remediation | `all_outcomes_are_valid_findings`, `active_service_passes` |
| `Severity` serialised in lowercase | `severity_serialises_as_variant_name` + the 6 module rule tests (9 tests) |
| Custom `Debug` for `Severity` | `severity_debug_output_is_variant_name` |
| `remediation` left out of JSON when `None` | `finding_serialises_with_all_fields` |
| `Send + Sync` removed from `ScanModule` | test build fails (`src/lib.rs` and `tests/public_api.rs`) |
| Only `Send` kept | test build fails ("cannot be shared between threads safely") |
| Only `Sync` kept | test build fails ("cannot be sent between threads safely") |

Before the step 4 tests were added, removing `Send + Sync` did **not** break
any test. That gap was found in a review after step 10 and is now closed.

## Result

```text
$ cargo test
     Running unittests src/lib.rs
test result: ok. 47 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
     Running tests/public_api.rs
test result: ok. 7 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

$ cargo clippy --all-targets -- -D warnings      → no warnings
$ cargo fmt --check                              → no changes
$ RUSTDOCFLAGS="-D warnings" cargo doc --no-deps → no warnings
```

Also run on Ubuntu 24.04 (container, unprivileged user): all 54 tests pass —
see [step-09-unit-tests.md](step-09-unit-tests.md#on-the-target-os-ubuntu-2404-container).
