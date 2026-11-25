# Demo agents in containers (`scripts/demo-agents.sh`)

**Repo:** `lunarscope-master` (`scripts/demo-agents.sh`)
**Date:** 2026-11-16
**Status:** Done, tested against a temporary master

## Why

To test the scans and the install flow on several "servers" with known
weaknesses, without real servers. Works together with the development
service from [dev-service.md](dev-service.md).

## What it does

```bash
scripts/demo-agents.sh            # create (or recreate) the demo agents
scripts/demo-agents.sh --remove   # delete the containers and their agents
```

1. Logs in on the master (`http://127.0.0.1:3030`; asks the dashboard
   password, or uses `LUNARSCOPE_PASSWORD`; the password goes to curl through
   stdin, so it is not visible in `ps`).
2. Saves the rule scan **`demo_baseline_scan`** (replaces an older version):
   `/etc/shadow` at most 640 (High), telnetd not installed (Critical), SSH
   `X11Forwarding no` (Low).
3. Deletes earlier agents with the demo hostnames, so running it twice
   doesn't make duplicates.
4. Starts four `ubuntu:24.04` containers in parallel and gives them their
   weaknesses:

   | Container | Set up as | Expected |
   |-----------|-----------|----------|
   | `web-01` | SSH `PermitRootLogin yes`, `PasswordAuthentication yes` | High root login, Medium password login |
   | `db-01` | SSH hardened, ufw configured, X11 forwarding off | only pending updates (the "good" server) |
   | `legacy-01` | telnetd installed, `/etc/shadow` mode 644, no SSH | Critical telnetd, High `/etc/shadow` |
   | `dev-01` | SSH without a `PasswordAuthentication` line (default: yes) | Medium password login |

   All of them also get High "pending security updates" (the image is older
   than the package lists) and Low "could not check UFW" (no systemd in a
   container).
5. For each container: **Agents → Add agent** with every scan on (built-in and
   rule scans, read from the form), then the **install command** from the
   master inside the container, then the agent as the `lunarscope` user.
6. Waits for the first scan of each agent and prints its `scan cycle` line.

The containers use the host network (the agent only allows plain http to
`localhost`), each with its own hostname (`--uts private`). They have no
systemd, so the agent is started directly; after a reboot run the script
again. `--init` makes them stop at once.

Options through the environment: `LUNARSCOPE_MASTER` (other URL),
`LUNARSCOPE_PASSWORD`.

## Test

Against a temporary master on `127.0.0.1:3031` (own database and test
password, so the `lunarscope` service was not touched):

First run (before the speed fixes below), 10 min 48 s:

```text
web-01     scan cycle: 8 finding(s) in 4123 ms; accepted 8, rejected 0, not sent 0
db-01      scan cycle: 8 finding(s) in 4141 ms; accepted 8, rejected 0, not sent 0
legacy-01  scan cycle: 7 finding(s) in 4114 ms; accepted 7, rejected 0, not sent 0
dev-01     scan cycle: 8 finding(s) in 4118 ms; accepted 8, rejected 0, not sent 0
```

Stored results (newest per check), as expected:

| Server | Critical | High | Medium | Low | Pass |
|--------|---------:|-----:|-------:|----:|-----:|
| web-01 | 0 | 2 (root login, updates) | 1 (password login) | 2 | 3 |
| db-01 | 0 | 1 (updates) | 0 | 1 (UFW) | 6 |
| legacy-01 | 1 (telnetd) | 2 (updates, /etc/shadow) | 0 | 3 | 1 |
| dev-01 | 0 | 1 (updates) | 1 (password login) | 2 | 4 |

`--remove`: deleted the 4 agents on the master and the 4 containers in 9 s;
0 agents left.

A second test run with the fixes below collided with a run started by hand
at the same time (same container names) and was stopped. The run by hand,
against the `lunarscope` service on port 3030 with the fixed script, worked
(confirmed by the user).

### Problems found while testing

| Problem | Fix |
|---------|-----|
| The scan list from the form also took the `scan_time` field (`name="scan_time"`), so `scan_time=on` was sent and the master answered 400; the script stopped without a message (`set -e` in a pipeline) | Only checkbox fields are read; every step now stops with a message (`die`) |
| Recreating a container waited 10 s (`sleep` as PID 1 ignores SIGTERM) | `podman run --init` |
| Installing took ~10 minutes (`openssh-server` recommends Python etc.) | `apt-get install --no-install-recommends` |
| `podman exec -d` printed container ids | Output discarded |

## Update for 0.4.0

| Change | Why |
|--------|-----|
| Logs in as `LUNARSCOPE_USER` (default `admin`) plus the password | Master 0.4.0 has user accounts; the user must be an admin |
| Reads a fresh `form_id` from the "Add agent" form for every agent | Master 0.4.0 refuses the form without it (protection against adding an agent twice) |
| The agent runs in a loop: `apply-update` as root, then the agent as `lunarscope`, started again 10 s after it exits | The containers have no systemd; this does what the unit file does, so "Update" under Settings → Agent updates also works on the demo agents |

Checks: `bash -n` ✅. The same login, `form_id` and loop code ran in the
0.4.0 end-to-end tests (containers `upd-test-01`, `e2e-040`). The full
script wasn't run again, because the four demo containers of the
`lunarscope` service were running and the script recreates them. Run it
yourself after `sudo systemctl restart lunarscope`:
`LUNARSCOPE_USER=admin scripts/demo-agents.sh`.

## Update 2026-11-25: two-step login and CSRF

Since master 0.6.0/0.6.1 the script could no longer log in or make changes:
with two-step login on, the password step only gives the code-step cookie,
and every change needs the session's CSRF token.

- `login` now asks for the code from the authenticator app when the master
  asks for it (or takes it from `LUNARSCOPE_CODE`) and posts it to
  `/login/mfa`. A wrong or reused code stops the script with a clear message.
- `page` sends `X-CSRF-Token`: the SHA-256 of `csrf:` and the session token,
  as the master computes it.

Checked against a test master (127.0.0.1:3078, temporary database, admin with
two-step login): login with a code from an independent TOTP script works; a
POST with the token gets through to the handler; the same POST without it
gets 403; a wrong code (`000000`) stops with "the code for admin was not
accepted".
