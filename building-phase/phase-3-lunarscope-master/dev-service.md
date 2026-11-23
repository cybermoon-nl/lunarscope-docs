# Development service `lunarscope` (master on the dev laptop)

**Repo:** `lunarscope-master` (`scripts/install-dev-service.sh`)
**Date:** 2026-11-16
**Status:** Script ready; install run by hand with sudo

## Why

To test a new build without starting the master by hand:

```bash
cargo build --release            # in lunarscope-master and/or lunarscope-agent
sudo systemctl restart lunarscope
```

## How it works

`scripts/install-dev-service.sh` (run once with sudo) creates the system
service `lunarscope` (`/etc/systemd/system/lunarscope.service`):

- **Every (re)start copies the newest release builds** from the repos
  (`ExecStartPre=+/usr/bin/install …`) to `/usr/local/bin/lunarscope-master`
  and `/usr/local/share/lunarscope/lunarscope-agent`, then starts the copy.
  A system service can't run a program from the home folder itself:
  SELinux (enforcing on Fedora) and `ProtectHome=true` block it. The `+`
  runs only the copy as root and outside the sandbox.
- The master runs as the system user `lunarscope` with the same hardening
  as `lunarscope-master.service`, on **`http://127.0.0.1:3030`** (port 3000
  is used by something else on this laptop).
- Database: `/var/lib/lunarscope/master.db` (`StateDirectory`).
- Secrets, made on the first install in `/etc/lunarscope` (root:lunarscope,
  640): a random `admin-token` (`openssl rand -hex 32`) and
  `dashboard-password`, the hash of a password you choose
  (`lunarscope-master hash-password`). A second run keeps them.
- `--agent-binary` points at the copied agent, so **Agents → Add agent**
  install links hand out the agent from the latest agent build.
- Running the script again updates the unit and restarts the service.

The paths in the unit come from where the script lives, so it works for any
checkout with `lunarscope-agent` next to `lunarscope-master`.

## Commands

| What | Command |
|------|---------|
| Install / update | `sudo scripts/install-dev-service.sh` |
| Test a new build | `cargo build --release` then `sudo systemctl restart lunarscope` |
| Logs | `journalctl -u lunarscope -f` |
| Show the unit without installing | `scripts/install-dev-service.sh --print-unit` |
| Remove | `sudo scripts/install-dev-service.sh --uninstall` (keeps `/etc/lunarscope`, `/var/lib/lunarscope` and the user) |

A build that doesn't start (e.g. a broken migration) shows up in
`systemctl status lunarscope` and the journal; after 5 failed starts in
5 minutes systemd stops trying until the next `restart`.

## Checks

| Check | Result |
|-------|--------|
| `bash -n` | ✅ |
| `--print-unit` + `systemd-analyze verify` | ✅ only "`/usr/local/bin/lunarscope-master` is not executable" (it doesn't exist until the first start copies it) |
| Without sudo / unknown option | Refused with "Run this with sudo", exit 1 |

Not done by Claude: the install itself (needs sudo).

## Update for 0.4.0

- **Login:** after the first restart with master 0.4.0 the database has
  user accounts. The master makes user **`admin`** from
  `/etc/lunarscope/dashboard-password` (only while there are no users yet),
  so log in as `admin` with the same password. Add more users under
  Settings → Users, or with `lunarscope-master add-user <name> [--viewer]
  --db /var/lib/lunarscope/master.db` (as the `lunarscope` user).
- **Signed agent updates:** the unit now also copies
  `lunarscope-agent/target/release/lunarscope-agent.sig` (made with
  `lunarscope-agent update-sign`) next to the agent binary, or removes an
  old one when there is none. Run `sudo scripts/install-dev-service.sh`
  once to get the new unit. See
  [change-0.4.0-agent-self-update.md](change-0.4.0-agent-self-update.md).
- **Backups:** daily copies go to `/var/lib/lunarscope/backups` (7 kept);
  history older than 90 days is deleted. See
  [change-0.4.0-history-cleanup-backups.md](change-0.4.0-history-cleanup-backups.md).
