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
| 10 | `cargo test` green + tag v0.1.0 | Done — tagged `v0.1.0` | [step-10](phase-1-lunarscope-modules/step-10-release-v0.1.0.md) |

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
| 21 | `cargo test` green + tag v0.1.0 | Checks green — commit + tag by user (still open) | [step-21](phase-2-lunarscope-agent/step-21-release-v0.1.0.md), [testing](phase-2-lunarscope-agent/testing.md) |

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
| 34 | `cargo test` green + tag v0.1.0 | Checks green — commit + tag by user | [step-34](phase-3-lunarscope-master/step-34-release-v0.1.0.md) |
