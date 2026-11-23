# Change (0.4.0) — CI up to date, `deny.toml`, vulnerable dependencies updated

**Repos:** `lunarscope-agent` 0.4.0, `lunarscope-master` 0.4.0
**Date:** 2026-11-16
**Status:** Done — checked locally with cargo-deny 0.21.0; not committed yet

## What was wrong

Both repos had the same `.github/workflows/ci.yml` (gitleaks, semgrep,
lint, test, dependency check, release on a `RELEASE-*` tag). Problems:

| Problem | Effect |
|---------|--------|
| No `deny.toml` | `cargo deny check` has no allowed licenses by default, so the dependency job could never pass |
| Master's release job uploaded `target/release/lunarscope-agent` | Copied from the agent repo; that file doesn't exist in the master repo, so a master release would fail |
| No `--locked` | CI could test other dependency versions than `Cargo.lock` says |
| Dependabot for Cargo commented out | Only GitHub Actions were watched |
| No `rust-version` | An old toolchain would fail with unclear errors (edition 2024, let-chains) |

## Changes

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` (both) | `--locked` on clippy, test, release build and `cargo deny`; master uploads `lunarscope-master`; agent release job has a note that the binary is signed offline, not in CI |
| `.github/dependabot.yml` (both) | Cargo block switched on (weekly) |
| `deny.toml` (new, both) | Advisories: vulnerabilities and yanked crates fail; unmaintained only for direct dependencies. Licenses: a list of permissive licenses (everything in the tree today). Bans: duplicate versions warn, wildcards fail. Sources: only crates.io, plus (agent) the `lunarscope-modules` git repo |
| `Cargo.toml` (both) | `rust-version = "1.99"`, `publish = false` (also tells cargo-deny not to check our own crate's license) |
| `Cargo.lock` (both) | Security updates, below |

### What cargo-deny found, and what was done

| Repo | Advisory | Fix |
|------|----------|-----|
| agent | RUSTSEC-2026-0346 / 0347 / 0348 / 0349 (rustls: TLS secrets in `Debug`, ECH data leak, Brotli 1 GiB allocation, ServerHello downgrade) | `rustls` 0.23.45 → 0.23.46 |
| agent | RUSTSEC-2026-0382 (webpki: distrusted intermediates accepted) | `rustls-webpki` 0.103.15 → 0.103.17 |
| agent | RUSTSEC-2026-0383 (bundled roots trust distrusted emSign intermediates) | `webpki-root-certs` 1.0.9 → 1.0.12 |
| master | RUSTSEC-2026-0385 (`ctutils`: not constant-time) | `ctutils` 0.4.2 → 0.4.8 |
| master | RUSTSEC-2026-0459 (bundled SQLite < 3.54 with a crafted `-wal` file) | **Ignored with a reason** in `deny.toml`: sqlx 0.9.0 pins `libsqlite3-sys` 0.37, and the master only opens its own database in `/var/lib/lunarscope` (owner `lunarscope`, mode 750), so nobody else can plant the files. Remove the ignore once sqlx allows `libsqlite3-sys` ≥ 0.39 |
| agent | `lunarscope-modules` has no license | Named with `[[licenses.clarify]]` as `LicenseRef-lunarscope` (our own code; doesn't pretend to be MIT). Replace once the modules repo gets a real license |

All were semver-compatible updates (`cargo update -p …`), no code changes.

## Checks

| Check | Agent | Master |
|-------|-------|--------|
| `cargo deny --locked check` | ✅ advisories, bans, licenses, sources ok | ✅ |
| `cargo test --locked` (after the updates) | ✅ 77 | ✅ 270 |
| `cargo clippy --locked --all-targets --all-features -- -D warnings` | ✅ | ✅ |
| `cargo fmt --check` | ✅ | ✅ |
| `cargo build --release --locked` | ✅ | ✅ |

The CI workflows themselves can only run on GitHub (self-hosted runner);
they weren't run here. cargo-deny was installed in a scratch folder for this
check, not in `~/.cargo`.

## Not changed

- Semgrep still runs with `|| true` (report only, never fails the build) —
  as before.
- The action versions (`actions/checkout@v4`, …): Dependabot keeps those up
  to date.
- `lunarscope-modules` CI: not part of this change.
