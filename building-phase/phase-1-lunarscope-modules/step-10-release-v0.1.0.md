# Step 10 — `cargo test` green + tag `v0.1.0`

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17 (checks re-run after adding tests for steps 1–4)
**Status:** Done — committed as `c8015c3` and tagged `v0.1.0` on 2026-10-17 17:57 (CEST), pushed to GitHub

## Goal

Confirm the library is complete and passes all checks, then tag it as
`v0.1.0` so `lunarscope-agent` can depend on a fixed version (step 11).

## Final checks

All checks were run from a clean state (`cargo clean`) with `--locked`, so
the build uses exactly the versions in `Cargo.lock`, as CI will.

| Check | Command | Result |
|-------|---------|--------|
| Debug build | `cargo build` | ✅ |
| Release build | `cargo build --release` | ✅ |
| Unit tests | `cargo test --locked` (`src/`) | ✅ 47 passed, 0 failed |
| Integration tests | `cargo test --locked` (`tests/public_api.rs`) | ✅ 7 passed, 0 failed |
| Doc tests | `cargo test` | ✅ 0 (none written) |
| Lint | `cargo clippy --all-targets --locked -- -D warnings` | ✅ no warnings |
| Formatting | `cargo fmt --check` | ✅ no changes |
| Docs | `RUSTDOCFLAGS="-D warnings" cargo doc --no-deps` | ✅ no warnings |
| Target OS | test binaries on Ubuntu 24.04 as an unprivileged user | ✅ 54 passed |
| Step 1 configuration | `cargo metadata`, `cargo tree`, `git check-ignore` (see step 1) | ✅ |

Not run locally: `cargo audit` and `cargo deny` are not installed on the dev
machine. They are part of the CI pipeline in phase 4 (step 36–37). The
library has only two direct dependencies (`serde`, `serde_json`).

## Contents of `v0.1.0`

| Item | Step |
|------|------|
| `Severity` enum (`Critical`, `High`, `Medium`, `Low`, `Pass`) | 2 |
| `Finding` struct (`check_name`, `severity`, `description`, `remediation`) | 3 |
| `ScanModule` trait (`Send + Sync`; `name`, `description`, `run`) | 4 |
| `SshScan` — `ssh_scan` | 5 |
| `FirewallScan` — `firewall_scan` | 6 |
| `PackageScan` — `package_scan` | 7 |
| `all_modules()` + re-exports | 8 |
| 54 tests (47 unit, 7 integration) | 2–9 |

### Files to commit in `lunarscope-modules`

```text
.gitignore                     (ignores /target)
Cargo.toml
Cargo.lock
src/lib.rs
src/modules/mod.rs
src/modules/ssh_scan.rs
src/modules/firewall_scan.rs
src/modules/package_scan.rs
tests/public_api.rs
```

`target/` is ignored and must not be committed.

## Commit and tag (done by hand)

Claude does not commit or tag; these are the exact commands.

### 1. `lunarscope-modules`

```bash
cd "repos/lunarscope-modules"
git add .gitignore Cargo.toml Cargo.lock src tests
git status   # check: only the files listed above, no target/
git commit -m "Add lunarscope-modules library with ssh, firewall and package scan modules"
git tag -a v0.1.0 -m "lunarscope-modules v0.1.0: Severity, Finding, ScanModule, ssh_scan, firewall_scan, package_scan"
git push origin main
git push origin v0.1.0
```

**Annotated tag (`-a`)** — it stores who tagged it, when, and a message,
unlike a lightweight tag. That is useful for traceability in the internship
report. The tag must be pushed separately; `git push` does not push tags by
default.

**Committing on `main`** — the repo only has `main` so far. The CI workflow
triggers on pushes to `develop`, `feature/**` and `fix/**`, and on pull
requests to `main`/`develop`. It runs on a self-hosted runner, which is not
installed yet (step 39). On a feature branch, the jobs would wait for a
runner that doesn't exist. Pushing to `main` and pushing the tag do not
trigger the workflow. Once the runner is set up in phase 4, new work can go
through `feature/**` branches and PRs.

### 2. `lunarscope-docs`

```bash
cd "repos/lunarscope-docs"
git add building-phase
git commit -m "Document building phase 1 (lunarscope-modules steps 1-10)"
git push origin main
```

### 3. Check

```bash
git -C repos/lunarscope-modules ls-remote --tags origin
```

The output should contain `refs/tags/v0.1.0`.

## How the agent will use this version (step 11)

```toml
[dependencies]
lunarscope-modules = { git = "https://github.com/cybermoon-nl/lunarscope-modules", tag = "v0.1.0" }
```

Pinning to `tag = "v0.1.0"` (instead of the default branch) means new commits
to the library never change the agent build without a deliberate version
bump.

Note: the architecture document has the URL as `.../lunarscape-modules`
(typo); the real remote is `https://github.com/cybermoon-nl/lunarscope-modules.git`.

## Next step

Phase 2, step 11 — `lunarscope-agent` binary crate with the git dependency on
`lunarscope-modules` `v0.1.0`.
