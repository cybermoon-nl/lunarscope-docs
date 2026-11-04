# Step 9 — Unit tests per module

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done

## Goal

From the guide: write `#[cfg(test)]` blocks that call `run()` and check that
the output has the right type and that `severity` is always filled in.

## Starting point

Most unit tests were written together with each module in steps 5–8 (at the
user's request), so this step was a review of those tests against the step 9
requirements:

| Requirement | Status before this step |
|-------------|-------------------------|
| `#[cfg(test)]` block per module | ✅ in `ssh_scan.rs`, `firewall_scan.rs`, `package_scan.rs`, `mod.rs`, `lib.rs` |
| Test calls `run()` | ✅ one test per module |
| Output has the right type | ✅ implicitly; made explicit with `let findings: Vec<Finding> = ...run();` |
| Severity always filled in | ⚠️ not checked explicitly; only `check_name` and `description` were checked |

### What "severity always filled in" means here

`severity` is a `Severity` enum, not an `Option`, so the compiler already
guarantees every `Finding` has one. A test can't make that fail. What *can*
go wrong, and matters to the master and the dashboard, are the related
rules:

1. The JSON value of `severity` must be one of the five strings the master
   expects (`"Critical"`, `"High"`, `"Medium"`, `"Low"`, `"Pass"`), never
   `null`/missing.
2. `remediation` must be filled in **exactly** when the check did not pass:
   a failing finding without a fix is useless to the admin, and a Pass with a
   "fix" is confusing.
3. `check_name` must be a known name and `description` must not be empty.

## What was done

### Shared invariant helper — `src/lib.rs`

```rust
#[cfg(test)]
pub(crate) fn assert_valid_finding(finding: &Finding, known_checks: &[&str]) {
    // 1. check_name is one of the module's known checks
    // 2. description is not empty/whitespace
    // 3. severity serialises to Critical/High/Medium/Low/Pass
    // 4. remediation is Some(non-empty) unless severity is Pass, and None for Pass
}
```

It is compiled only for tests (`#[cfg(test)]`) and is `pub(crate)`, so it is
not part of the library's public API. Every module uses the same helper, so
all modules follow the same rules.

### Per module

Each module got:

- a `CHECKS` constant listing its valid `check_name`s;
- **`all_outcomes_are_valid_findings`** — runs the module's pure logic for
  every possible outcome and passes each finding through
  `assert_valid_finding`:
  - `ssh_scan`: empty config, hardened, insecure, key-only root, unexpected
    values, missing file
  - `firewall_scan`: active+enabled, active+disabled, active+no conf,
    inactive, failed, systemctl error
  - `package_scan`: sample output, real Ubuntu output, up to date, empty
    output, apt error
- the existing `run()` test, renamed to **`run_returns_valid_findings`**
  (`run_returns_one_valid_finding` for the firewall). It now has an explicit
  `Vec<Finding>` type and uses `assert_valid_finding` instead of only
  checking names and descriptions.

## Choices and justification

- **Test every outcome, not just the one on the test machine** — `run()`
  only produces the outcome of the machine the test runs on (on the Fedora
  dev machine, for example, always "unreadable" for SSH and "no apt" for
  packages). Running all outcomes through the pure functions checks the
  rules for findings that a given machine never produces.
- **One shared helper instead of copies** — the rules are the contract with
  the master. If they change (e.g. a new severity), there is one place to
  update.
- **No coverage tool** — `cargo-llvm-cov` / `cargo-tarpaulin` are not
  installed on the dev machine. Instead, coverage was checked by hand with
  the outcome tables in each step document and with mutation testing (below).
  A coverage job can be added to CI in phase 4 if wanted.

## Verification

### Mutation check of the new helper

| Bug introduced | Failing tests |
|----------------|---------------|
| `ssh_password_authentication` Medium finding returns `remediation: None` | `all_outcomes_are_valid_findings`, `password_authentication_yes_is_medium` |
| Firewall Pass finding returns a remediation | `all_outcomes_are_valid_findings`, `active_service_passes` |

### Local

```text
$ cargo test
     Running unittests src/lib.rs
test result: ok. 42 passed; 0 failed
     Running tests/public_api.rs
test result: ok. 4 passed; 0 failed

$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

### On the target OS (Ubuntu 24.04 container)

The compiled test binaries (`cargo test --no-run`) and a small example that
prints the findings of `all_modules()` were run in the
`docker.io/library/ubuntu:24.04` container as an **unprivileged
`lunarscope` user**, in three states. All 46 tests passed in all three.
(After the extra tests for steps 1–4 were added, all 54 tests were run again
in the container and passed — see [testing.md](testing.md).)

| State | `ssh_*` | `firewall_ufw_active` | `package_*` |
|-------|---------|-----------------------|-------------|
| Bare image | `ssh_config_readable` Low (no sshd installed) | Low (no systemctl) | security High (2), regular Pass |
| `openssh-server` + `ufw` installed | root login Pass (`prohibit-password` default), password auth **Medium** (Ubuntu default `yes`) | Low (systemd not running) | both Pass (install pulled in the updates) |
| After `ufw --force enable` | same | Low (systemd not running) | both Pass |

Observations:

- With the **real Ubuntu 24.04 `sshd_config`** (including its
  `Include /etc/ssh/sshd_config.d/*.conf` line), as the unprivileged user, the
  module reads the file and reports the correct defaults.
- A container has no systemd as PID 1, so `systemctl` fails. The firewall
  module correctly reports that as a Low "could not check" finding instead of
  crashing or giving a false result. The firewall **Pass** path on a real
  systemd host is so far only covered by unit tests; it will be verified on a
  real server in the end-to-end test (step 33).
- systemctl's error message here spans two lines, so the description
  contains a newline. That's harmless (HTML collapses it on the dashboard),
  but noted in case the master displays descriptions in a `<pre>` block.

Findings JSON per state is stored in
[`evidence/step-09-ubuntu-container/`](evidence/step-09-ubuntu-container/).

## Next step

Step 10 — `cargo test` green + tag `v0.1.0`. The tag will be left to the user,
because nothing is committed or tagged by Claude.
