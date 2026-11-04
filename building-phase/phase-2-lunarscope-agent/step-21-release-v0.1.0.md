# Step 21 — `cargo test` green + tag `v0.1.0`

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** All checks green — commit and tag are done by hand (see below)

## Final checks

Run from a clean state (`cargo clean`) with `--locked`:

| Check | Command | Result |
|-------|---------|--------|
| Debug build | `cargo build --locked` | ✅ |
| Release build | `cargo build --release --locked` | ✅ 3,208,664 bytes |
| Tests | `cargo test --locked` | ✅ **33 passed**, 0 failed |
| Lint | `cargo clippy --all-targets --locked -- -D warnings` | ✅ no warnings |
| Formatting | `cargo fmt --check` | ✅ no changes |
| Docs | `RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --document-private-items` | ✅ |
| Script | `bash -n scripts/measure.sh` | ✅ |
| Unit file | `systemd-analyze verify` / `security --offline=yes` | ✅ / exposure 1.2 OK |
| Target OS | measurements on Ubuntu 24.04 (step 19), systemd run (step 20) | ✅ |
| Mutation checks | 9 deliberate bugs, each caught (see [testing.md](testing.md)) | ✅ |

Not run locally: `cargo audit` / `cargo deny` (not installed; phase 4 CI).

## Files to commit in `lunarscope-agent`

```text
.gitignore                    (ignores /target)
Cargo.toml
Cargo.lock
config.toml                   (example, placeholders only)
lunarscope-agent.service
scripts/measure.sh
src/main.rs
src/config.rs
src/sender.rs
```

## Commit and tag (done by hand)

From `repos/lunarscope-agent`:

```bash
git add .gitignore Cargo.toml Cargo.lock config.toml lunarscope-agent.service scripts src
git status
git commit -m "Add lunarscope-agent: config, module registry, scan loop, HTTPS reporting, systemd unit"
git tag -a v0.1.0 -m "lunarscope-agent v0.1.0"
git pull --rebase origin main
git push origin main
git push origin v0.1.0
```

If `git pull --rebase` rewrites the commit (as happened with the modules repo,
where the remote had a CI commit), the tag points to the old commit. Delete
and re-create it before pushing it:

```bash
git tag -d v0.1.0
git tag -a v0.1.0 -m "lunarscope-agent v0.1.0"
```

To avoid this, run `git pull --rebase origin main` **before** creating the tag.

Docs, from `repos/lunarscope-docs`:

```bash
git add building-phase
git commit -m "Document building phase 2 (lunarscope-agent steps 11-21)"
git push origin main
```

## Notes for phase 4 (CI/CD)

- **The agent repo's `.github/workflows/ci.yml` is still the original
  template** (Semgrep + placeholder lint). The modules repo already has the
  newer workflow (gitleaks, clippy, test, audit/deny). Steps 35–36 should bring
  the agent repo up to the same level.
- **Licences for `deny.toml` (step 37).** The guide plans to allow
  MIT/Apache-2.0/ISC. The agent's dependency tree (`cargo tree --format {l}`)
  also contains **`Unicode-3.0`** (ICU crates, via `url`/`idna`),
  **`BSD-3-Clause`** and the combined licence of `aws-lc-sys`
  (`ISC AND (Apache-2.0 OR ISC) AND Apache-2.0 AND MIT AND BSD-3-Clause AND …`).
  These are permissive licences, but `cargo deny` will fail unless they are
  added to the allow-list.
- **Build on Ubuntu 24.04** — the release binary links against glibc; building
  on the target OS (self-hosted runner) avoids glibc version mismatches.

## Next step

Phase 3, step 22 — `lunarscope-master`.
