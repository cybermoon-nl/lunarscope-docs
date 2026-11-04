# Step 20 — systemd unit file

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

## Goal

`lunarscope-agent.service` with `ExecStart`, `Restart=on-failure`,
`User=lunarscope` and `WantedBy=multi-user.target`.

## What was done

`lunarscope-agent.service` in the repo root:

```ini
[Unit]
Description=Lunarscope security scan agent
Documentation=https://github.com/cybermoon-nl/lunarscope-agent
Wants=network-online.target
After=network-online.target
# Stop restarting after 5 failed starts in 5 minutes (e.g. a broken config).
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=lunarscope
Group=lunarscope
ExecStart=/usr/local/bin/lunarscope-agent --config /etc/lunarscope/config.toml
Restart=on-failure
RestartSec=10

# Hardening: the agent only reads files, runs read-only commands
# (systemctl is-active, apt-get -s) and makes outbound HTTPS requests.
NoNewPrivileges=true
CapabilityBoundingSet=
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallErrorNumber=EPERM
ProtectProc=invisible
RemoveIPC=true
UMask=0077
# AF_UNIX is needed for systemctl (D-Bus), AF_INET/AF_INET6 for the master.
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
```

### Installation (as tested)

Requirements on the server:

- Ubuntu 24.04 (the binary links against its glibc, see step 19).
- The **`ca-certificates`** package. The agent loads the system's trusted
  CAs to verify the master's TLS certificate; without them it stops at
  startup with `could not create HTTP client: … (is the ca-certificates
  package installed?)`. A normal Ubuntu server install has it; minimal
  images (containers) may not. Added in agent v0.1.1, see
  [fix-0.1.1-ca-certificates.md](fix-0.1.1-ca-certificates.md).

```bash
sudo apt-get install ca-certificates
sudo useradd --system --no-create-home --shell /usr/sbin/nologin lunarscope
sudo install -m 755 lunarscope-agent /usr/local/bin/lunarscope-agent
sudo install -d -m 750 -o root -g lunarscope /etc/lunarscope
sudo install -m 640 -o root -g lunarscope config.toml /etc/lunarscope/config.toml
sudo install -m 644 lunarscope-agent.service /etc/systemd/system/lunarscope-agent.service
sudo systemctl daemon-reload
sudo systemctl enable --now lunarscope-agent
journalctl -u lunarscope-agent -f
```

Testing an installation by hand, without waiting for the service:

```bash
sudo -u lunarscope /usr/local/bin/lunarscope-agent --config /etc/lunarscope/config.toml --once
```

## Choices and justification

### Required parts from the guide

- `ExecStart=… --config /etc/lunarscope/config.toml` — the path from the
  architecture document (6.3).
- `Restart=on-failure` + `RestartSec=10` — restarts after a crash or a
  failed start. Network errors don't need a restart, because the agent
  handles them itself (step 18).
- `User=lunarscope` — an unprivileged system user. Every module was designed
  to work without root (`sshd_config` is `0644`, `systemctl is-active`,
  `apt-get -s`, `ufw.conf` is `0644`).
- `WantedBy=multi-user.target` — starts at boot.

### Additions

- **`StartLimitIntervalSec=300` + `StartLimitBurst=5`** — with a broken
  config the agent exits at once. Without a limit, systemd would restart it
  every 10 s forever and fill the journal. Now it gives up after 5 failed
  starts in 5 minutes and shows `failed`.
- **`Wants=/After=network-online.target`** instead of `After=network.target`
  (architecture document): `network.target` doesn't wait for an IP address,
  so the first scan's requests could fail. The agent would recover on the next
  tick, but that is an hour later.
- **Hardening.** The architecture document listed `NoNewPrivileges`,
  `ProtectSystem=strict` and `ReadWritePaths=/var/lib/lunarscope`. Changes:
  - `ReadWritePaths` was **dropped**: the agent writes nothing, and systemd
    refuses to start a service whose `ReadWritePaths` directory doesn't exist.
  - A full sandbox was added (no capabilities, read-only OS, no `/home`,
    private `/tmp` and devices, no kernel tuning/modules/logs, syscall filter,
    no `/proc` view of other processes, `UMask=0077`, only Unix/IPv4/IPv6
    sockets). `AF_UNIX` is needed for `systemctl` (D-Bus), and the syscall
    filter `@system-service` still allows the `systemctl`/`apt-get` child
    processes.
  - `systemd-analyze security`: exposure **1.2 "OK"** (scale 0–10, lower is
    better). For comparison: 3.0 after the first hardening round, and 9.0
    "UNSAFE" for the same unit with only `User=lunarscope` and no hardening.
  - Not used: `PrivateNetwork` (the agent needs the network),
    `IPAddressDeny` (the master's IP isn't known in advance),
    `ProtectProc=ptraceable`/`ProcSubset=pid` (could break `apt-get`).

## Checks

### Static

```text
$ systemd-analyze verify ./lunarscope-agent.service
lunarscope-agent.service: Command /usr/local/bin/lunarscope-agent is not executable: No such file or directory
```

The only message is that the binary isn't installed on the dev machine, which
is expected. There are no syntax or unknown-option errors.

```text
$ systemd-analyze security --offline=yes ./lunarscope-agent.service
→ Overall exposure level for lunarscope-agent.service: 1.2 OK :-)
```

### Real systemd run (Ubuntu 24.04 container booted with systemd)

The installation steps above were run in an `ubuntu:24.04` image with systemd,
`openssh-server` and `ufw`, with `ufw --force enable`, against a fake master
on `127.0.0.1` and `interval_seconds = 10`
([full output](evidence/step-20-systemd-container-run.txt)):

| Check | Result |
|-------|--------|
| `systemctl status` | `active (running)`, Tasks: 1 |
| Runs as | `lunarscope` user, 4.8 MB RSS |
| Every module works inside the sandbox | ✅ 5 findings per cycle, all accepted: root login Pass, password auth **Medium** (Ubuntu default), **UFW active Pass**, 2 security updates **High**, regular Pass |
| Cycles | every 10 s (3 cycles in 22 s, 15 requests) |
| `ufw disable` | firewall finding becomes **High: "UFW service is running but the firewall is disabled (ENABLED=no …)"**, while `systemctl is-active ufw` still prints `active` |
| Broken config (`"package-scan"`) | 4 restarts, then `Start request repeated too quickly` → `failed`; the reason is in the journal 4× |

This run also closes two open points from phase 1:

- The firewall **Pass** path is now verified on a real systemd host. In step 9
  it was only covered by unit tests, because the container had no systemd.
- The `ENABLED=no` check from step 6 is confirmed to be needed: after
  `ufw disable`, systemd keeps reporting `ufw.service` as `active`.

The only journal warning was `ProtectHostname=yes … UTS namespace setup is
prohibited (container manager?)`, a container limitation. On a real server
the namespace is created.

## Next step

Step 21 — all checks green + tag `v0.1.0`.
