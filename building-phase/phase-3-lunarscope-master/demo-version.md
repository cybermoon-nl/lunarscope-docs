# Demo version (`lunarscope-demo`)

**Folder:** `repos/lunarscope-demo` (no git repo yet)
**Date:** 2026-11-17
**Status:** Built and tested locally; not yet put on a server

## Why

To ask companies for a letter of intent, they should be able to see
Lunarscope working. That needs a public demo, kept strictly apart from the
real code and from the dev setup, so nothing gets mixed up. The user chose
a **full copy** of the code (over a deploy kit that installs the real
builds): the demo can then be changed on its own.

## What is in it

| Part | What |
|------|------|
| `master/` | Copy of `lunarscope-master` 0.4.1, package and binary renamed to `lunarscope-demo`; demo banner on every page and the login page (EN/NL); `demo-agents.sh` defaults to port 3040; the dev service script, the real unit file and `.github` removed |
| `agent/` | Copy of `lunarscope-agent` 0.4.0, unchanged (runs only in the demo containers) |
| `deploy/upload.sh` | Laptop: builds both (release, `--locked`) from this folder only and copies them with the deploy files to a server |
| `deploy/setup-server.sh` | Server, as root: caddy, podman, ufw (SSH/80/443), unattended-upgrades, user `lunarscope-demo`, `/opt`, `/etc`, `/var/lib/lunarscope-demo`, admin password, service, Caddyfile, health check. Running it again updates and keeps the data |
| `deploy/lunarscope-demo.service` | Like the real unit (same hardening), `127.0.0.1:3040`, `--public-url https://<domain>`, 30 days history, 7 backups |
| `deploy/Caddyfile` | Like `install/Caddyfile`, plus `X-Robots-Tag: noindex` |
| `README.md` | How to deploy, read-only accounts for companies, what to do by hand (SSH keys only), rules (sample data only) |

`.git` was not copied, so a push from this folder can't reach the real
repos. Changes in the real repos are not copied over automatically.

## Separation from the real product

| | Real | Demo |
|---|---|---|
| Binary | `lunarscope-master` | `lunarscope-demo` |
| Service, port | `lunarscope`, 3030 | `lunarscope-demo`, 3040 |
| Data | `/var/lib/lunarscope` | `/var/lib/lunarscope-demo` |

The one overlap: the demo's `demo-agents.sh` uses the same container
names (`web-01`, …) as the dev demo, so it must only run on the demo
server (in the README).

## Checks

| Check | Result |
|-------|--------|
| Demo master: `cargo test --locked`, clippy, fmt, release build | ✅ 273 tests (the page test now also checks the banner on every page) |
| Demo agent: `cargo test --locked`, release build | ✅ 77 |
| `bash -n` on `upload.sh`, `setup-server.sh`, `demo-agents.sh` | ✅ |
| `caddy validate` on the Caddyfile (domain filled in) | ✅ |
| `systemd-analyze verify` on the unit | ✅ (only "binary not there yet") |
| Binaries in `ubuntu:24.04` and `debian:13` containers | ✅ run |
| Binaries in `debian:12` | ❌ need glibc 2.39 (built on Fedora) — README and script say Ubuntu 24.04 / Debian 13; `setup-server.sh` stops with a clear message on an older system |
| Demo master on `127.0.0.1:3041` | Banner on login (EN and NL) and dashboard; `admin` made from the password file; per-address lockout works |

Not tested: `setup-server.sh` and `upload.sh` against a real server (needs
the server, a domain, and root there). The first real run will show
whether Caddy gets its certificate and whether anything in the script
needs adjusting.

## Update 2026-11-17: `sync-from-master.sh`

The demo is now brought up to date with `lunarscope-demo/sync-from-master.sh`
instead of by hand: it copies the real master and agent again, re-applies
the demo patches (name, banner, port 3040, removed files) with checks that
stop when a patch no longer fits, runs the 284 tests on the copy and only
then replaces `master/` and `agent/`. Used three times for 0.5.0
([change-0.5.0-ui-feedback.md](change-0.5.0-ui-feedback.md)); each run:
tests green, banner present, `demo-agents.sh` on port 3040.

## Update 2026-11-25: demo 0.8.0

The demo follows master 0.8.0 ([change-0.8.0-email-server-only-in-file.md](change-0.8.0-email-server-only-in-file.md)).
Changes to the demo itself:

- `sync-from-master.sh` now copies `deploy/` into its work folder and patches
  the Caddy test in `master/src/main.rs` to read
  `../../deploy/lunarscope-demo.service` and `../../deploy/Caddyfile`,
  because the real unit file is removed in the demo.
- `deploy/lunarscope-demo.service` passes `--smtp-file
  /etc/lunarscope-demo/smtp.toml`.
- The README has an "E-mail (optional)" paragraph: without that file the
  e-mail page shows a notice and nothing is sent.

Sync result: demo master 0.8.0 (374 tests; synced again after the two extra tests: 375), demo agent 0.5.1 (77 tests), both
release builds with `--locked` OK, banner and port 3040 present.
