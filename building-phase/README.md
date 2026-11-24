# Building phase

Implementation log for the Lunarscope prototype. Every step from the
step-by-step guide gets its own file, describing what was done, why, and how
it was verified.

| Phase | Repo | Steps |
|-------|------|-------|
| 1 | `lunarscope-modules` (shared library) | 1 – 10 |
| 2 | `lunarscope-agent` | 11 – 21 |
| 3 | `lunarscope-master` | 22 – 34 |
| 4 | CI/CD (agent + master) | 35 – 40 |

## Architecture

- [Architecture as built](architecture-as-built.md): the system as built (master 0.6.1, agent 0.4.1) next to the architecture design document, with every difference (D1–D19) and why, the 9-table data model, and four small inconsistencies to fix.
- [Fix 0.6.1 — Caddy proxies to port 3000](phase-3-lunarscope-master/fix-0.6.1-caddy-port.md): the Caddyfile pointed at the dev port 3030 while the service listens on 3000 (502 on a fresh install); a test now keeps them equal.
- [Fix 0.6.1 — Semgrep blocks the build](phase-3-lunarscope-master/fix-0.6.1-semgrep-blocking.md): `|| true` removed in the CI of master, agent and modules; findings 47/18/17 fixed to 0 (pinned actions, Dependabot cooldown, test secrets, one rule excluded).
- [Change 0.6.1 — CSRF tokens](phase-3-lunarscope-master/change-0.6.1-csrf-tokens.md): every dashboard change (24 forms, HTMX, logout) needs a per-session token (hash of the session token); 403 without it, 413 for too big bodies; 10 mutation checks.
- [Fix 0.6.1 — CI on the self-hosted runner, vulnerable dependencies](phase-3-lunarscope-master/fix-0.6.1-ci-runner-and-dependencies.md): Docker and workspace ownership on the runner, gitleaks false positive, `libsqlite3-sys` 0.40 and `url` 2.5.9 (two advisories), token for the private modules repo, `deny.toml` for modules.
- [Change 0.7.0 — SMTP server from a config file](phase-3-lunarscope-master/change-0.7.0-smtp-config-file.md): `--smtp-file /etc/lunarscope/smtp.toml` (mode 640 checked) keeps the SMTP server and password out of the database; the page shows the server read-only; 4 mutation checks (one needed an extra test); not tried on a real SMTP server.
- [Change 0.2.0 — `lunarscope_scan` (modules 0.2.0, master 0.7.0, agent 0.5.0)](phase-1-lunarscope-modules/change-0.2.0-lunarscope-scan.md): Lunarscope checks its own installation (11 checks for agent and master), migration 0010 and EN/NL texts in the master, agent dependency; 9 mutation checks, all caught.
- [Live test 2026-11-24 — agent self-update and two-step login](phase-3-lunarscope-master/test-2026-11-24-agent-update-and-mfa.md): signed update 0.5.0 to 0.5.1 with a throwaway key and four refusal cases; MFA with an independent TOTP and QR scans; real phone and SMTP not tested.

## Re-checks

- [2026-11-04 — date check and full re-test](retest-2026-11-04.md): 219/219 tests pass on Fedora and Ubuntu 24.04; one small agent finding (unclear error without `ca-certificates`).
- [Agent v0.1.1 — clear error without `ca-certificates`](phase-2-lunarscope-agent/fix-0.1.1-ca-certificates.md): fix for the re-test finding; own error kind, full error chain and a hint.
- [Agent v0.2.0 — daily scan at a fixed time](phase-2-lunarscope-agent/change-0.2.0-daily-scan-time.md): `scan_time = "02:00"` (UTC) replaces `interval_seconds`; the master's stale limit goes from 2 h to 25 h (released in master v0.2.0).
- [Master v0.2.0 — login for the dashboard](phase-3-lunarscope-master/change-0.2.0-dashboard-login.md): the dashboard pages need a password (Argon2 hash in `--password-file`, made with `lunarscope-master hash-password`); sessions, logout, lockout after 5 wrong passwords.
- [Agent code overview](phase-2-lunarscope-agent/code-overview.md): what each file and function of the agent does (v0.4.0).
- [Agent + master v0.3.0 — new GUI, agent management, rule scans](phase-3-lunarscope-master/change-0.3.0-agent-management.md): reference design with EN/NL, switch scans per agent and set the scan time without reinstalling, one-time install command from "Add agent", rule scans (TOML) sent to the agents, Report page.
- [Fix 0.3.0 — fixed problems no longer stay on the dashboard](phase-3-lunarscope-master/fix-0.3.0-stale-findings.md): after a complete scan the agent sends `POST /api/scan-complete`; the master removes checks that weren't reported any more.
- [Development service `lunarscope`](phase-3-lunarscope-master/dev-service.md): run the master as a systemd service on the dev laptop; `sudo systemctl restart lunarscope` picks up the newest builds.
- [Demo agents in containers](phase-3-lunarscope-master/demo-agents.md): `scripts/demo-agents.sh` starts four Ubuntu containers with known weaknesses and installs the agent on them through "Add agent".
- [0.4.0 — Scan now, new install link, `/healthz`, no double agents](phase-3-lunarscope-master/change-0.4.0-scan-now-install-link-health.md)
- [0.4.0 — history cleanup and daily backups](phase-3-lunarscope-master/change-0.4.0-history-cleanup-backups.md): `--keep-days` (90), `--backups` (7), `VACUUM INTO` while running.
- [0.4.0 — time zone in a Settings page](phase-3-lunarscope-master/change-0.4.0-time-zone-settings.md): times shown in the chosen zone; scan times are local and sent to agents as UTC (summer/winter time handled).
- [0.4.0 — user accounts, read-only role, audit log](phase-3-lunarscope-master/change-0.4.0-user-accounts.md): log in with a user name; `admin` is made from the old dashboard password.
- [0.4.0 — signed agent self-update](phase-3-lunarscope-master/change-0.4.0-agent-self-update.md): Update buttons; releases signed offline with a key the master never has.
- [0.4.0 — HTTPS with Caddy](phase-3-lunarscope-master/change-0.4.0-https-caddy.md): `install/Caddyfile`, TLS 1.3, security headers.
- [0.4.0 — CI, `deny.toml`, dependency security updates](phase-3-lunarscope-master/change-0.4.0-ci-and-dependencies.md): rustls, webpki, ctutils updated; one SQLite advisory ignored with a reason.
- [0.4.1 — login lockout per address](phase-3-lunarscope-master/change-0.4.1-login-limit-per-address.md): 5 wrong passwords lock only that address (behind Caddy: from `X-Forwarded-For`), 100 in total lock everyone.
- [Demo version (`lunarscope-demo`)](phase-3-lunarscope-master/demo-version.md): separate copy of master and agent with a demo banner and a Hetzner deploy kit, for showing it to companies.
- [0.5.0 — UI feedback](phase-3-lunarscope-master/change-0.5.0-ui-feedback.md): Servers tab, last + previous scan, Change scans page with confirmation, dashboard filters, clickable new findings, 24h/AM-PM setting, Dutch by default.
- [Master code overview](phase-3-lunarscope-master/code-overview.md): what each file, table, route and function of the master does (v0.4.0).

## Progress

### Phase 1 — `lunarscope-modules`

| Step | Description | Status | Log |
|------|-------------|--------|-----|
| 1 | Repo + crate setup (`lunarscope-modules`) | Done | [step-01](phase-1-lunarscope-modules/step-01-crate-setup.md) |
| 2 | `Severity` enum | Done | [step-02](phase-1-lunarscope-modules/step-02-severity-enum.md) |
| 3 | `Finding` struct | Done | [step-03](phase-1-lunarscope-modules/step-03-finding-struct.md) |
| 4 | `ScanModule` trait | Done | [step-04](phase-1-lunarscope-modules/step-04-scanmodule-trait.md) |
| 5 | `ssh_scan` module | Done | [step-05](phase-1-lunarscope-modules/step-05-ssh-scan.md) |
| 6 | `firewall_scan` module | Done | [step-06](phase-1-lunarscope-modules/step-06-firewall-scan.md) |
| 7 | `package_scan` module | Done | [step-07](phase-1-lunarscope-modules/step-07-package-scan.md) |
| 8 | `mod.rs` + public exports | Done | [step-08](phase-1-lunarscope-modules/step-08-mod-exports.md) |
| 9 | Unit tests per module | Done | [step-09](phase-1-lunarscope-modules/step-09-unit-tests.md), [testing](phase-1-lunarscope-modules/testing.md) |
| 10 | `cargo test` green + tag v0.1.0 | Done — tagged `v0.1.0` on 2026-10-17 | [step-10](phase-1-lunarscope-modules/step-10-release-v0.1.0.md) |

### Phase 2 — `lunarscope-agent`

| Step | Description | Status | Log |
|------|-------------|--------|-----|
| 11 | Repo + binary crate | Done | [step-11](phase-2-lunarscope-agent/step-11-crate-setup.md) |
| 12 | `Config` struct + loading | Done | [step-12](phase-2-lunarscope-agent/step-12-config.md) |
| 13 | Example `config.toml` | Done | [step-13](phase-2-lunarscope-agent/step-13-config-toml.md) |
| 14 | Module registry | Done | [step-14](phase-2-lunarscope-agent/step-14-module-registry.md) |
| 15 | Scan loop | Done | [step-15](phase-2-lunarscope-agent/step-15-scan-loop.md) |
| 16 | HTTP POST to master | Done | [step-16](phase-2-lunarscope-agent/step-16-http-post.md) |
| 17 | Interval timer | Done | [step-17](phase-2-lunarscope-agent/step-17-interval-timer.md) |
| 18 | Error handling | Done | [step-18](phase-2-lunarscope-agent/step-18-error-handling.md) |
| 19 | Release binary + size/memory | Done | [step-19](phase-2-lunarscope-agent/step-19-release-build.md) |
| 20 | systemd unit file | Done | [step-20](phase-2-lunarscope-agent/step-20-systemd-unit.md) |
| 21 | `cargo test` green + tag v0.1.0 | Done — tagged `v0.1.0` on 2026-11-04 | [step-21](phase-2-lunarscope-agent/step-21-release-v0.1.0.md), [testing](phase-2-lunarscope-agent/testing.md) |

### Phase 3 — `lunarscope-master`

| Step | Description | Status | Log |
|------|-------------|--------|-----|
| 22 | Repo + binary crate | Done | [step-22](phase-3-lunarscope-master/step-22-crate-setup.md) |
| 23 | Database setup (migrations) | Done | [step-23](phase-3-lunarscope-master/step-23-database-setup.md) |
| 24 | Database connection (`init_db`) | Done | [step-24](phase-3-lunarscope-master/step-24-database-connection.md) |
| 25 | `POST /api/scan-result` | Done | [step-25](phase-3-lunarscope-master/step-25-api-scan-result.md) |
| 26 | API key validation as separate function | Done | [step-26](phase-3-lunarscope-master/step-26-api-key-validation.md) |
| 27 | `POST /api/register-agent` | Done | [step-27](phase-3-lunarscope-master/step-27-register-agent.md) |
| 28 | Tera templates | Done | [step-28](phase-3-lunarscope-master/step-28-tera-templates.md) |
| 29 | Dashboard `GET /` | Done | [step-29](phase-3-lunarscope-master/step-29-dashboard-route.md) |
| 30 | Server detail `GET /server/{agent_id}` | Done | [step-30](phase-3-lunarscope-master/step-30-server-detail.md) |
| 31 | HTMX refresh | Done | [step-31](phase-3-lunarscope-master/step-31-htmx-refresh.md) |
| 32 | Axum router + serve | Done | [step-32](phase-3-lunarscope-master/step-32-router-and-server.md) |
| 33 | End-to-end test | Done | [step-33](phase-3-lunarscope-master/step-33-end-to-end-test.md) |
| 34 | `cargo test` green + tag v0.1.0 | Done — tagged `v0.1.0` on 2026-11-04 | [step-34](phase-3-lunarscope-master/step-34-release-v0.1.0.md) |
