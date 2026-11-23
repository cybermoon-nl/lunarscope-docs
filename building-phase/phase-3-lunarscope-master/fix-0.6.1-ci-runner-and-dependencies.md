# Fix 0.6.1: CI on the self-hosted runner, vulnerable dependencies

The CI of master, agent and modules had never passed on the self-hosted
runner (`CBMN-Github-Runner`, Ubuntu 24.04). After semgrep was made blocking
([fix-0.6.1-semgrep-blocking.md](fix-0.6.1-semgrep-blocking.md)) the runs were
followed job by job and every failure was fixed.

| # | Repo | Job | Failure | Fix |
|---|------|-----|---------|-----|
| 1 | all | gitleaks, semgrep | `docker: command not found`: these jobs run in a container | Docker installed on the runner (`docker.io`), runner user in group `docker` (done on the runner) |
| 2 | all | lint, test, dependency-check | `EACCES … .git/FETCH_HEAD`: the container jobs run as root and leave root-owned files in the shared workspace | Last step of both container jobs (`if: always()`): `chown -R` the workspace to the owner of the folder above it (the runner user). Once by hand: `chown -R newuser:newuser ~/actions-runner/_work` |
| 3 | master | gitleaks | `generic-api-key` in `src/totp.rs:256` (commit `cae2fe6`): the base32 form of the public RFC 6238 test key | The test no longer writes the key out (length, prefix and round trip instead); the old commit's finding is in `.gitleaksignore` with the reason |
| 4 | master | dependency-check | `RUSTSEC-2026-0459` (`libsqlite3-sys` 0.37, SQLite CVE) | `sqlx` 0.9.0 → 0.9.1 allows `libsqlite3-sys` < 0.41: updated to **0.40.0**. The ignore for this advisory in `deny.toml` (from 0.4.0, "blocked by sqlx 0.9.0") is removed |
| 5 | master, agent | dependency-check | `RUSTSEC-2026-0592` (`url` 2.5.8, stack overflow in `Url::origin()`) | `url` → **2.5.9** (`cargo update -p url --precise 2.5.9`) |
| 6 | agent | lint, test | `failed to authenticate` fetching the git dependency `lunarscope-modules`: that repository is **private** and the job's `GITHUB_TOKEN` can only read the agent repository | The cargo jobs get `CARGO_NET_GIT_FETCH_WITH_CLI=true` and `GIT_CONFIG_COUNT/KEY_0/VALUE_0`, which rewrite the modules URL to one with the read-only token in the secret `MODULES_READ_TOKEN`. Environment only: nothing is written to the runner's git config; GitHub masks the secret in logs |
| 7 | modules | dependency-check | `cargo deny`: no `deny.toml` (every license rejected), then `LicenseRef-lunarscope` (the crate itself) not allowed | `deny.toml` added with the same rules as agent and master, `LicenseRef-lunarscope` allowed |
| 8 | modules | build (on `RELEASE-*` tags) | Copied from the agent: uploaded a `lunarscope-agent` binary that a library doesn't have | Builds the library only; the release has no files |

Also: `--locked` on every cargo command in the modules CI, like in agent and
master.

## Needed once, outside the code

- On the runner: Docker, the runner user in `docker`, the `chown` above, and
  `build-essential` + `pkg-config` (C compiler for `ring`, `aws-lc-sys` and
  the bundled SQLite).
- A fine-grained personal access token (resource owner `cybermoon-nl`,
  repository `lunarscope-modules` only, permission *Contents: read-only*),
  stored as secret `MODULES_READ_TOKEN` in `lunarscope-agent`, for Actions
  and for Dependabot (Dependabot PRs don't get Actions secrets).

## Checks

| Check | Result |
|-------|--------|
| gitleaks (image `zricethezav/gitleaks`, full history) | master, agent, modules: no leaks |
| semgrep `--config=auto --error` | 0 findings in all three |
| `cargo fmt --check`, `cargo clippy --locked --all-targets --all-features -D warnings` | clean in all three |
| `cargo test --locked --all-features` | master 366, agent 77, modules 54 passed |
| `libsqlite3-sys` / `url` in `Cargo.lock` | 0.40.0 / 2.5.9 (master), `url` 2.5.9 (agent) |
| Licenses of every dependency against each `deny.toml` (from `cargo metadata`) | all allowed (the crates themselves are skipped: `publish = false` or clarified) |
| URL rewrite with a token (`git ls-remote` of the modules tag, empty `HOME`) | with token: tag found; without: `could not read Password`, the CI error |
| `cargo audit` / `cargo deny` locally | **not run** (tools not installed); checked in CI |
