# Step 34 — `cargo test` green + tag `v0.1.0`

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done — committed as `3ee83ee` and tagged `v0.1.0` on 2026-11-04 12:12 (CET), pushed to GitHub. Docs committed as `7ec4a5a` (12:27).

> **Update 2026-11-16:** v0.2.0 adds a dashboard login and the 25 h stale limit; see [change-0.2.0-dashboard-login.md](change-0.2.0-dashboard-login.md).

## Final checks

Run from a clean state (`cargo clean`) with `--locked`:

| Check | Command | Result |
|-------|---------|--------|
| Debug build | `cargo build --locked` | ✅ |
| Release build | `cargo build --release --locked` | ✅ 8,057,624 bytes |
| Tests | `cargo test --locked` | ✅ **132 passed**, 0 failed |
| Lint | `cargo clippy --all-targets --locked -- -D warnings` | ✅ no warnings |
| Formatting | `cargo fmt --check` | ✅ no changes |
| Docs | `RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --document-private-items` | ✅ |
| Unit file | `systemd-analyze verify` / `security --offline=yes` | ✅ / exposure 1.2 OK |
| End-to-end | real agent + master, locally and as systemd services on Ubuntu 24.04 (step 33) | ✅ |
| Mutation checks | every step 23–32 (see each step) | ✅ every deliberate bug caught |

Not run locally: `cargo audit` / `cargo deny` (not installed; phase 4 CI).

### Tests per file

| File | Tests | Covers |
|------|------:|--------|
| `src/routes/api.rs` | 28 | `POST /api/scan-result` (17), `POST /api/register-agent` (11) |
| `src/db/mod.rs` | 26 | both migrations, constraints, `init_db` options |
| `src/routes/dashboard.rs` | 17 | `GET /`, latest-per-check logic, sorting, stale, HTMX fragment |
| `src/routes/server.rs` | 15 | `GET /server/{agent_id}`, 404, escaping, HTMX fragment |
| `src/auth.rs` | 15 | SHA-256, Bearer parsing, both extractors, admin token, key generation |
| `src/templates.rs` | 14 | all templates, escaping, `render_block` |
| `src/main.rs` | 9 | arguments, combined router, real socket + graceful shutdown |
| `src/time.rs` | 3 | date formatting (50 years day by day) |
| `src/routes/static_files.rs` | 3 | embedded htmx (pinned SHA-256), serving |
| `src/models.rs` | 2 | severity names |
| **Total** | **132** | |

## Contents of `lunarscope-master` v0.1.0

| Item | Step |
|------|------|
| Crate with axum 0.8, tokio, sqlx 0.9 (bundled SQLite 3.51.3), tera 2 | 22 |
| Migrations `0001_initial` (`agents`, `scan_results`) and `0002_latest_results`, embedded | 23, 29 |
| `init_db`: WAL, foreign keys, busy timeout, migrations at startup | 24 |
| `POST /api/scan-result`: Bearer key (SHA-256), agent id check, ±60 s replay window, validation | 25 |
| `AuthenticatedAgent` extractor | 26 |
| `POST /api/register-agent` with admin token; UUID v4 + 256-bit `lsk_` key | 27 |
| Embedded Tera templates, autoescaped | 28 |
| `GET /` dashboard (latest result per check, worst first, stale marking) | 29 |
| `GET /server/{agent_id}` detail page | 30 |
| HTMX refresh every 30 s (fragment only), htmx 2.0.11 embedded | 31 |
| `--listen`, graceful shutdown on SIGTERM | 32 |
| `lunarscope-master.service` (hardened, `StateDirectory`) | 33 |

### Files to commit in `lunarscope-master`

```text
.gitignore                      (/target)
Cargo.toml, Cargo.lock
build.rs
lunarscope-master.service
migrations/0001_initial.sql
migrations/0002_latest_results.sql
src/  (main.rs, auth.rs, error.rs, models.rs, templates.rs, time.rs,
       db/mod.rs, db/queries.rs,
       routes/mod.rs, routes/api.rs, routes/dashboard.rs, routes/server.rs, routes/static_files.rs)
static/htmx.min.js, static/htmx.LICENSE
templates/base.html, dashboard.html, server.html, not_found.html
```

## State of the repositories (2026-11-04, after `git fetch`, before the release commits)

*Update 2026-11-04: all points in this table were resolved the same day. Agent and master are committed and tagged `v0.1.0`, the docs are committed, and the `edition = "2026"` change in `lunarscope-modules` was reverted. All four repos are clean and in sync with GitHub.*

| Repo | Local commits | GitHub ahead by | Uncommitted | Tag |
|------|---------------|-----------------|-------------|-----|
| `lunarscope-modules` | up to date | 0 | **`Cargo.toml`: `edition = "2026"`** (see below) | `v0.1.0` ✅ |
| `lunarscope-agent` | none since "first commit" | **1** (`cbfe07f` CI update, only `ci.yml`) | phase 2 files | — (step 21 still open) |
| `lunarscope-master` | none since "first commit" | **1** (`5962da8` CI update, only `ci.yml`) | phase 3 files | — |
| `lunarscope-docs` | up to date | 0 | `building-phase/` | — |

The two remote CI commits only change `.github/workflows/ci.yml`, which is not
among the new files, so a **fast-forward pull** works. Their workflows run on
`develop`, `feature/**`, `fix/**`, on `RELEASE-*` tags and on pull requests,
**not** on pushes to `main` or on the `v0.1.0` tags. Pushing the commands
below therefore doesn't start a pipeline. The self-hosted runner doesn't
exist yet (step 39).

## Commit and tag (done by hand)

**Pull first, then commit and tag**, so the tag ends up on the commit that is
pushed (in phase 1 the tag had to be re-created after a rebase).

### 1. `lunarscope-agent` (phase 2, step 21)

```bash
cd repos/lunarscope-agent
git pull --ff-only origin main
git add .gitignore Cargo.toml Cargo.lock config.toml lunarscope-agent.service scripts src
git status
git commit -m "Add lunarscope-agent: config, module registry, scan loop, HTTPS reporting, systemd unit"
git tag -a v0.1.0 -m "lunarscope-agent v0.1.0"
git push origin main
git push origin v0.1.0
```

### 2. `lunarscope-master` (this step)

```bash
cd repos/lunarscope-master
git pull --ff-only origin main
git add .gitignore Cargo.toml Cargo.lock build.rs lunarscope-master.service migrations src static templates
git status
git commit -m "Add lunarscope-master: API, agent registration, dashboard with HTMX, systemd unit"
git tag -a v0.1.0 -m "lunarscope-master v0.1.0"
git push origin main
git push origin v0.1.0
```

### 3. `lunarscope-docs`

```bash
cd repos/lunarscope-docs
git add building-phase
git commit -m "Document building phases 1-3 (steps 1-34)"
git push origin main
```

### 4. Check

```bash
git -C repos/lunarscope-agent ls-remote --tags origin
git -C repos/lunarscope-master ls-remote --tags origin
```

Both should list `refs/tags/v0.1.0`.

### `lunarscope-modules`: uncommitted `edition = "2026"` (resolved: reverted on 2026-11-04)

The local `lunarscope-modules/Cargo.toml` still has an uncommitted change
from 2026-10-20: `edition = "2026"`. cargo 1.98 doesn't know that edition,
so the local checkout doesn't build. **Don't commit it.** If it wasn't
intentional, undo it with:

```bash
git -C repos/lunarscope-modules checkout Cargo.toml
```

The agent isn't affected; it uses the `v0.1.0` tag from GitHub.

## Notes for phase 4 (CI/CD)

- **`cargo deny` (step 37)** needs more licences on the allow-list than
  MIT/Apache-2.0/ISC. Master: `Unicode-3.0`, `BSD-3-Clause`, `Zlib`,
  `BSL-1.0`, `Unlicense OR MIT`. Agent: also the combined licence of
  `aws-lc-sys` (agent step 21). The new CI's `dependency-check` job runs
  `cargo deny check`, which also needs a `deny.toml` in each repo.
- **gitleaks** scans the full history. `static/htmx.min.js` is minified
  third-party code. If gitleaks reports false positives in it, add an
  allowlist entry for that one path in `.gitleaks.toml`, not a global rule.
  A custom rule for `lsk_[0-9a-f]{64}` (master API keys, step 27) is worth
  adding.
- **`cargo clippy --all-features`** in the new CI is fine: neither crate
  defines features.
- **Deployment** (not part of the guide's steps): the TLS reverse proxy
  (step 32) and both systemd units (agent step 20, master step 33) on the
  VPS / customer servers.

## Next step

Phase 4, step 35 — CI/CD: gitleaks job.
