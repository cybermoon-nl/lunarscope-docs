# Step 7 — Third module: `package_scan`

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done (verified with unit tests and in an Ubuntu 24.04 container)

## Goal

Create `src/modules/package_scan.rs`: run `apt-get -s upgrade`, parse the
output for pending updates and return one finding per package category.

## What was done

### Files

| File | Change |
|------|--------|
| `src/modules/package_scan.rs` | New — the `PackageScan` module + unit tests |
| `src/modules/mod.rs` | Added `pub mod package_scan;` |

### Structure of the module

```rust
pub struct PackageScan;

impl ScanModule for PackageScan {
    fn name(&self) -> &str { "package_scan" }
    fn description(&self) -> &str { "Checks for pending security and regular package updates via apt" }
    fn run(&self) -> Vec<Finding> {
        let output = simulate_upgrade();
        evaluate(output.as_deref().map_err(String::as_str))
    }
}
```

| Function | Responsibility |
|----------|----------------|
| `simulate_upgrade()` | Runs `apt-get -s upgrade` with `LC_ALL=C`; returns stdout, or stderr/IO error as `Err` |
| `parse_upgrades(output)` | Turns every `Inst` line into an `Upgrade { name, security }` |
| `evaluate(output)` | Pure function: splits upgrades into categories and builds the findings |
| `category_finding(...)` | Builds the finding for one category (Pass when empty) |

### What `apt-get -s upgrade` prints

For each package that would be upgraded, the simulation prints an `Inst`
line with the current version in `[...]` and the new version plus the
archives ("pockets") it comes from in `(...)`:

```text
Inst openssl [3.0.13-0ubuntu3.1] (3.0.13-0ubuntu3.4 Ubuntu:24.04/noble-updates, Ubuntu:24.04/noble-security [amd64])
Inst tzdata [2024a-2ubuntu1] (2025b-0ubuntu0.24.04 Ubuntu:24.04/noble-updates [all])
```

The first is a security update (it is in `noble-security`), the second is a
regular update.

### Package categories and findings

| `check_name` | Category | Severity when pending | Pass when |
|--------------|----------|-----------------------|-----------|
| `package_security_updates` | New version comes from a `*-security` pocket | **High** | none pending |
| `package_other_updates` | All other updates (`-updates`, `-backports`, …) | **Low** | none pending |
| `package_updates_checkable` | apt-get can't be run or fails (instead of the two above) | **Low** | — |

Description example: `3 pending security update(s): openssl, curl, libcurl4t64`.
At most 10 names are listed, followed by `and N more`. The remediation is
`sudo apt update && sudo apt upgrade`.

## Choices and justification

- **Categories based on the origin pocket** — the guide asks for "a finding
  per package category". The most useful split for an SMB admin is "has a
  known security fix" vs "regular update". Ubuntu and Debian publish
  security fixes in a separate `*-security` pocket (`noble-security`,
  Debian `stable-security`, Ubuntu Pro `noble-apps-security`). apt shows the
  pocket(s) for each upgrade, so no external CVE database is needed. The
  SQ6 PoC used a hard-coded fake CVE list; this module uses real data from
  the system's own package manager.
- **Only the origins are matched, not the package name** — the text after
  the `(` is searched for `-security`, so a package called e.g.
  `python3-security-tools` from `noble-updates` is not counted as a security
  update.
- **Only `Inst` lines are counted** — `Conf` lines repeat the same packages,
  and the "kept back" list contains packages `upgrade` will *not* install
  (usually phased updates or kernel packages that need new dependencies).
- **High for security updates, Low for regular updates** — pending security
  fixes mean known, published vulnerabilities on the server. Regular updates
  are good hygiene but not a direct security risk. The module does not try
  to judge each CVE (that would need a vulnerability database), so it does
  not use Critical.
- **Two findings, always** — like the other modules, each check returns a
  Pass when there is nothing to do, so the dashboard can show "up to date".
- **`apt-get -s` (simulate)** — needs no root and changes nothing on the
  system, so it works for the unprivileged `lunarscope` agent user (step 20).
  `apt-get` is used instead of `apt` because `apt` warns that its CLI output
  is not stable for scripts.
- **`LC_ALL=C`** — keeps apt's output in English on every server locale, so
  the parser doesn't depend on the server's language settings.
- **Name list capped at 10** — keeps findings (and the `scan_results` rows /
  JSON payload) small on servers with hundreds of pending updates; the full
  count is always shown.

### Limitations (known, accepted for the prototype)

- **The result is only as fresh as the package lists.** The agent can't run
  `apt update` (needs root). Ubuntu 24.04 refreshes the lists daily via
  `apt-daily.timer`, so results can be up to about a day old. If that timer
  is disabled, the module may report "no pending updates" while there are.
- **Kept-back packages are not reported.** They can include security fixes,
  e.g. during a phased rollout, but `upgrade` would not install them either.
- **apt-based systems only** (Ubuntu/Debian). On other systems the module
  returns the `package_updates_checkable` Low finding.

## Verification

### Unit tests

12 tests in `package_scan.rs` (11 written with the module, 1 added after the container check) (details in [testing.md](testing.md)).
They use a sample `apt-get -s upgrade` output in the Ubuntu 24.04 format
(simulation notice, kept-back list, `Inst` and `Conf` lines). Full suite:

```text
$ cargo test
test result: ok. 38 passed; 0 failed

$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

To check that the tests are meaningful, deliberate bugs were introduced one
at a time and reverted:

| Bug introduced | Failing tests |
|----------------|---------------|
| Search the whole line for `-security` (incl. package name) | `security_in_package_name_is_not_a_security_update` |
| Also count `Conf` lines | `parses_only_inst_lines`, `pending_updates_give_one_finding_per_category` |
| No truncation of the name list | `long_package_lists_are_truncated` |
| Every update treated as security | `pending_updates_give_one_finding_per_category`, `long_package_lists_are_truncated` |

### On a real system

**Development machine (Fedora, no `apt-get`):** `run()` returns the
`package_updates_checkable` Low finding with "No such file or directory", as
expected.

**Ubuntu 24.04 container.** To test the happy path against real apt output,
the module was run in the official `docker.io/library/ubuntu:24.04` image with
podman:

1. A small example binary that prints `PackageScan.run()` as JSON was built
   on the host (`cargo build --release --example ...`; the example was
   removed afterwards). Its highest glibc requirement is `GLIBC_2.39`, which
   matches Ubuntu 24.04's glibc, so the host binary runs in the container
   unchanged.
2. In the container, `apt-get update` was run as root, then an
   **unprivileged user `lunarscope`** was created. The scan was run as that
   user, the same way the agent will run it (step 20).
3. Three situations were tested:

| Situation | Real `Inst` lines | Findings |
|-----------|-------------------|----------|
| Fresh image | `libsystemd0`, `libudev1` from `noble-security` | security **High** "2 pending security update(s): libsystemd0, libudev1"; regular **Pass** |
| `apt` downgraded to the release version `2.7.14build2` (newer `2.8.3` only in `noble-updates`) | the two above + `apt` from `noble-updates` | security **High** (2); regular **Low** "1 pending regular update(s): apt" |
| After `apt-get upgrade` | none | both **Pass** |

All results match what was expected. Findings from the second run:

```json
[
  {
    "check_name": "package_security_updates",
    "severity": "High",
    "description": "2 pending security update(s): libsystemd0, libudev1",
    "remediation": "Run 'sudo apt update && sudo apt upgrade'"
  },
  {
    "check_name": "package_other_updates",
    "severity": "Low",
    "description": "1 pending regular update(s): apt",
    "remediation": "Run 'sudo apt update && sudo apt upgrade'"
  }
]
```

Confirmed by this run:

- `apt-get -s upgrade` works as a **non-root** user (exit code 0), so the
  agent does not need root for this module.
- The real format matches the parser. One difference from the hand-written
  test sample: real apt **interleaves** `Inst` and `Conf` lines per package
  instead of grouping them. The parser handles both, because it only looks
  at lines starting with `Inst`.
- No code changes were needed. The captured output of the second run was
  added as a permanent fixture (`REAL_UBUNTU_2404`) with its own test,
  `real_ubuntu_output_is_categorised` (38 tests in total).

Raw outputs are stored in
[`evidence/step-07-ubuntu-container/`](evidence/step-07-ubuntu-container/):

| File | Content |
|------|---------|
| `apt-output.txt` / `findings.json` | Fresh image |
| `apt-output-mixed.txt` / `findings-mixed.json` | After downgrading `apt` |
| `findings-after.json` | After `apt-get upgrade` |

## Next step

Step 8 — `mod.rs` + public exports.
