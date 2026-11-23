# Fix 0.6.1: Semgrep in CI blocks the build

## Problem

Found while comparing the code with the architecture design
([architecture-as-built.md](../architecture-as-built.md), section 8, item 2):
the Semgrep job in `.github/workflows/ci.yml` ended in `|| true`, so findings
never failed the build, although the design says the scan "makes sure no
unsafe code passes".

The `|| true` is now removed in the CI of all three repositories
(`lunarscope-master`, `lunarscope-agent`, `lunarscope-modules`). To be able to
do that, the findings had to be fixed first.

## Local run

Semgrep ran locally with the image `docker.io/semgrep/semgrep`, command
`semgrep --config=auto --error`.

| Repo | Findings before | Findings after |
|------|-----------------|----------------|
| `lunarscope-master` | 47 | 0 (with one excluded rule, see below) |
| `lunarscope-agent` | 18 | 0 |
| `lunarscope-modules` | 17 | 0 |

Exit code 0 in all three after the fixes.

| Rule | What | Where | Fixed by |
|------|------|-------|----------|
| `github-actions-mutable-action-tag` | actions used by tag, which can be moved | all 3 repos | pin to commit SHA |
| `dependabot-missing-cooldown` | no cooldown on new versions | all 3 repos | `cooldown` in `dependabot.yml` |
| `detected-generic-secret` (4) | base32 strings in TOTP tests | master | computed in the test |
| `django-no-csrf-token` (25) | forms without `{% csrf_token %}` | master | CSRF tokens added; rule excluded |

15 "PartialParsing" warnings on the templates remain. They are warnings and do
not fail the run.

## Fixes

- **Actions pinned to commit SHAs** (with the version in a comment): checkout
  `11d5960…` (v4.4.0), upload-artifact `ea165f8…` (v4.6.2), cache `0057852…`
  (v4.3.0), action-gh-release `3bb1273…` (v2.6.2), `dtolnay/rust-toolchain`
  `3900882…` (the `stable` branch). The toolchain action took its version
  from the ref name before; the pinned commit does not, so the input
  `toolchain: stable` was added. Why: a tag can be moved by whoever controls
  the action's repository; a commit hash cannot, so a compromised tag cannot
  run in our CI.
- **`cooldown: default-days: 7`** per ecosystem in `.github/dependabot.yml`.
  Dependabot waits a week after a release before proposing it, so a hijacked
  release has time to be found and pulled.
- **`src/totp.rs` tests** (master): the RFC 6238 test key was written as
  literal base32 strings, which looked like secrets (4 findings). The tests
  now compute it with `base32_encode(RFC_KEY)`. No production code changed;
  the tests check the same values.
- **`|| true` removed** in the three `ci.yml` files.

## The excluded rule

`python.django.security.django-no-csrf-token.django-no-csrf-token` is excluded
in the master CI (with a comment in the file). Semgrep reads the Tera
templates (`templates/*.html`) as Django templates and asks for
`{% csrf_token %}` in every form, which does not exist in Tera (25 findings).
The real protection is the token added in
[change-0.6.1-csrf-tokens.md](change-0.6.1-csrf-tokens.md): all 24 dashboard
forms carry a hidden `csrf` field that the server checks. The one form the
rule would still want is not a form on a logged-in page (the login forms have
no session; see that document). The exclusion is the one rule excluded; all
others stay on.

## What remains unpinned

The container images `gitleaks:latest` and `semgrep/semgrep` in CI are not
pinned to a digest. Semgrep did not flag them, so they are left; pinning them
would be a later hardening step (with the cost that someone must update the
digest to get new rules).

## Checks

| Check | Result |
|-------|--------|
| Semgrep local, master / agent / modules | 0 / 0 / 0 findings, exit 0 |
| `cargo test` (master) | passing (366 with the CSRF change) |
| `cargo fmt --check`, `cargo clippy --all-targets -D warnings` | clean |

CI itself was not run on GitHub (nothing committed yet).
