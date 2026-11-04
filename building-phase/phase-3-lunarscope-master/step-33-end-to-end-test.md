# Step 33 — End-to-end test

**Repos:** `lunarscope-master`, `lunarscope-agent` (and `lunarscope-modules` v0.1.0)
**Date:** 2026-11-04
**Status:** Done

## Goal

Start the master locally, start the agent locally with `master_url` pointing
at localhost, and check that findings end up in the database and on the
dashboard.

## What was tested

The test was done twice:

1. **Locally** on the development machine (Fedora), exactly as the guide
   describes: both release binaries, plain HTTP on `127.0.0.1`.
2. **On the target OS**: master and agent installed as **systemd services** in
   an Ubuntu 24.04 container booted with systemd, with real `openssh-server`,
   `ufw` and `apt`. This includes "fixing" findings and restarting the master.

Release binaries used: agent 3,208,664 bytes, master 8,057,624 bytes. Both
need at most glibc 2.39 (agent) / 2.34 (master), so the binaries built on the
dev machine run unchanged on Ubuntu 24.04 (glibc 2.39). The agent uses
`lunarscope-modules` **v0.1.0** from GitHub (pinned commit `c8015c3`).

## 1. Local run

### Steps

```bash
openssl rand -hex 32 > admin-token && chmod 600 admin-token
lunarscope-master --db ./master.db --listen 127.0.0.1:38133 --admin-token-file ./admin-token

curl -H "Authorization: Bearer $(cat admin-token)" -H 'Content-Type: application/json' \
     -d '{"hostname":"fedora"}' http://127.0.0.1:38133/api/register-agent      # → 201, id + key

# agent.toml: agent_id + api_key from the answer, master_url = "http://127.0.0.1:38133",
#             interval_seconds = 10, all three modules
lunarscope-agent --config ./agent.toml
```

Port 38133 was used because port 3000 is already taken on the dev machine
(step 32). It makes no difference to the test.

### Results

| Check | Result |
|-------|--------|
| Registration | 201 Created |
| Agent cycles | every 10 s, `accepted 3, rejected 0, not sent 0` each time ([agent log](evidence/step-33-local-agent.log)) |
| Database after 4 cycles | 12 rows in `scan_results`, 3 in `latest_results` (one per check), agent `hostname = fedora`, `last_seen` = time of the last cycle |
| Findings | `firewall_ufw_active` High, `package_updates_checkable` Low, `ssh_config_readable` Low — correct for Fedora (no UFW, no apt, `sshd_config` is root-only) |
| Dashboard in the browser | row "fedora · High · 0/1/0/2/0", htmx 2.0.11 loaded from the master |
| **Master stopped** for 15 s (SIGTERM) and started again | master: "shutting down", "stopped", then "ready, 1 registered agent(s)"; agent: one cycle `not sent 3` with "Connection refused", the next cycle `accepted 3`, **without restarting the agent**; no data lost (15 → 18 rows) |
| Open dashboard during the outage | stayed on the page (same document), kept refreshing afterwards (2 HTMX swaps), no console errors |

## 2. Ubuntu 24.04 with systemd

### Setup

Installed with the documented commands (agent step 20, master
`lunarscope-master.service` added in this step):

- system user `lunarscope`; both binaries in `/usr/local/bin`;
- `/etc/lunarscope/admin-token` and `/etc/lunarscope/config.toml`, both
  `root:lunarscope 640`;
- `lunarscope-master.service`: `--listen 127.0.0.1:3000`, database in
  `/var/lib/lunarscope` (created by `StateDirectory=`);
- agent registered with `curl` against the running service; its config was
  written from the answer; `lunarscope-agent.service` started with
  `interval_seconds = 10`.

### Results

| Check | Result |
|-------|--------|
| Both services | `active (running)`, `User=lunarscope`, 0 restarts |
| Processes | master 8.8 MB RSS, 19 threads; agent 5.0 MB RSS, 1 thread |
| Agent journal | `scan cycle: 5 finding(s) in ~1.2 s; accepted 5` every 10 s |
| Master journal | `registered agent e85b7035-… (4e9cbc10fda8)`; no errors |
| Database files | only in `/var/lib/lunarscope` (`master.db`, `-wal`, `-shm`), owner `lunarscope`, mode `600`, directory `750` |

**Real findings of the fresh server:**

| Module | Check | Severity | Description |
|--------|-------|----------|-------------|
| firewall_scan | firewall_ufw_active | **High** | UFW service is running but the firewall is disabled (ENABLED=no in /etc/ufw/ufw.conf) |
| package_scan | package_security_updates | **High** | 3 pending security update(s): liblzma5, libpcre2-8-0, zlib1g |
| ssh_scan | ssh_password_authentication | **Medium** | SSH accepts password logins (PasswordAuthentication yes) |
| ssh_scan | ssh_permit_root_login | Pass | Root login over SSH only allows keys (PermitRootLogin prohibit-password) |
| package_scan | package_other_updates | Pass | No pending regular updates |

**The admin fixes two findings** (`ufw allow OpenSSH`, `ufw --force enable`,
`apt-get upgrade`):

| Check | Result |
|-------|--------|
| Next cycle (5 s later) | `firewall_ufw_active` → **Pass**, `package_security_updates` → **Pass** in `latest_results` |
| History kept | `scan_results` for the firewall check: High, High, … then Pass |
| Dashboard | worst status went from High to **Medium** (only password login left) |
| Detail page | 5 checks, Medium first |

**Master restarted** with `systemctl restart lunarscope-master` while the
agent kept running: graceful stop ("shutting down", "stopped"), back up
("listening on http://127.0.0.1:3000"), and the agent's next cycles were all
accepted (25 → 30 rows). The restart was quicker than the agent's interval,
so not a single result was lost.

Evidence: [journal](evidence/step-33-ubuntu-journal.txt),
[database](evidence/step-33-ubuntu-database.txt),
[dashboard HTML](evidence/step-33-ubuntu-dashboard.html),
[detail page HTML](evidence/step-33-ubuntu-server.html). The admin token and
API keys are not in the evidence files (checked with `grep lsk_`).

## New file: `lunarscope-master.service`

Added to the master repo for this test, as the counterpart of the agent's
unit (agent step 20) and the architecture document (6.4):

- `ExecStart=/usr/local/bin/lunarscope-master --db /var/lib/lunarscope/master.db --listen 127.0.0.1:3000 --admin-token-file /etc/lunarscope/admin-token`
- `StateDirectory=lunarscope` creates `/var/lib/lunarscope` for the
  `lunarscope` user and makes it the only writable path. This replaces the
  architecture's `ReadWritePaths=/var/lib/lunarscope`, which fails if the
  directory doesn't exist (agent step 20).
- The same hardening as the agent, plus `ProcSubset=pid` (the master starts
  no child processes). `systemd-analyze security`: **1.2 "OK"**.
- `Restart=on-failure`, `RestartSec=5`, and the same start limit as the agent.

## What this test covers, and what it doesn't

Covered end-to-end, with real binaries and no test doubles: config loading,
module registry, all three modules on Ubuntu, HTTP POST with Bearer key and
timestamp, key validation, replay window, storage in `scan_results` and
`latest_results`, `last_seen`/hostname updates, agent registration,
dashboard and detail rendering, HTMX refresh, recovery after a master
outage, graceful shutdown, and both systemd units with their sandboxes.

Not covered here:

- **HTTPS between agent and master.** Locally and in the container the master
  is on `http://127.0.0.1` (allowed for localhost only). In production a TLS
  reverse proxy sits in front (step 32). The agent's TLS 1.3 and certificate
  checks were already tested against a real TLS server (agent step 16).
  Setting up the proxy is deployment work.
- **Agent and master on different machines** (network between them). With
  TLS that's the same request as here, through the proxy.

## Next step

Step 34 — all tests green + tag `v0.1.0` for the master.
