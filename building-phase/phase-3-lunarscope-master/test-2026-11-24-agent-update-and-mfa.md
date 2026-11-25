# Live test (2026-11-24) — agent self-update and two-step login

**Repos:** `lunarscope-master` 0.7.0, `lunarscope-agent` 0.5.0 / 0.5.1
**Status:** Done; both tests passed. Not done: a real phone for the QR code,
and a real SMTP server.

Both tests ran against a **test master** (version 0.7.0, `127.0.0.1:3078`,
temporary database). The service `lunarscope` on port 3030 was not touched.

## 1. Agent self-update end to end

**Set-up.** A throwaway key pair; a scratch copy of the agent with that
public key in `update-key.pub`. The repo's `update-key.pub` still holds **no
key**, so updates are off in every real build until the owner makes one. A
new podman container `ls-update-test` (Ubuntu 24.04, host network, an agent
loop like `scripts/demo-agents.sh`). Agent 0.5.0 installed with **Add agent**
and the install link; all 4 scans, including `lunarscope_scan`, pre-checked.
The container was removed afterwards.

### Self-check findings

| Step | Result |
|------|--------|
| First scan after install | 10 findings; all 6 agent self-checks **Pass** (the install script sets the config to 640 `root:lunarscope` and the binary to 755 root) |
| After `chmod 644` on the config, `chmod 777` on the binary, `User=root` in the unit, then **Scan now** | `config_private` **High**, `binary` **Critical**, `service` **High** |

### Update

| Step | Expected | Result |
|------|----------|--------|
| Master restarted with a signed 0.5.1 binary, **Update** button | 303 | 303 |
| Agent log | download, check, stage | "the master offers version 0.5.1, downloading", "checked and staged" |
| Agent exit | code 75, restart | exit 75, "installed update: lunarscope-agent 0.5.1", restarted as 0.5.1 |
| Master | new version, request cleared | `agent_version` 0.5.1, `update_requested` 0 |

### Refusals

| Case | Result |
|------|--------|
| Binary without signature | master: "no signed update"; Update button 409 |
| Signed older version (0.5.0) | agent ignores it and stays on 0.5.1 |
| Signed with another key (0.5.2) | agent: "the signature doesn't match the built-in update key" |
| Binary changed after signing | master refuses to start: ".sig was made for another binary" |

## 2. Two-step login (MFA) end to end

**Set-up.** The same test master. An **independent Python TOTP** acts as the
phone; `zbarimg` (in a throwaway container) reads the QR codes.

### Setup and recovery PDF

| Check | Result |
|-------|--------|
| QR on the Account page | scans to `otpauth://totp/Lunarscope%20(127.0.0.1):admin?…secret=<key>`; key matches |
| QR in the recovery PDF | scans to the same URI; key matches |
| Turn on with a code | 303 to `?done=on` |
| Recovery PDF right after, without code | 200 `application/pdf` |
| Account page after setup | no autofocus code field |
| Key printed in the PDF text | equals the secret |

### Login

| Check | Result |
|-------|--------|
| Password only | redirect to `/login/mfa` |
| Wrong code | 401 |
| Right code | `/` with a session |
| Same code again | 401 (one-time use) |
| Recovery key typed in lower case with spaces | `/account?done=recovered`, two-step login off |
| Set up again | new key |
| Old recovery key | 401 |
| `reset-mfa admin --db` | two-step login off; audit "(command line) two-step login reset" |

## Not tested

- **A real phone** scanning the QR code (an authenticator app); the QR codes
  were decoded with `zbarimg` only.
- **A real SMTP server** for the e-mail report and the SMTP file
  ([change 0.7.0](change-0.7.0-smtp-config-file.md)).
- The update with the real release key: none exists yet.

## Follow-up 2026-11-25: real key, real phone

Done by the user on the development master (`lunarscope` service, 3030),
after the tests above:

| Step | Result |
|------|--------|
| Update key made with `update-keygen ~/.config/lunarscope`; public key committed in `update-key.pub` of the agent | Every agent build since then has the key built in |
| Four demo agents (web-01, db-01, legacy-01, dev-01) installed with agent 0.5.0 through `scripts/demo-agents.sh` (now with two-step login and CSRF) | All four on 0.5.0 |
| Agent 0.5.1 built, signed locally with `update-sign`, master restarted (signed update 0.5.1) | Offered on Settings → Lunarscope updates |
| Update for one agent, then for all | All four agents on **0.5.1** |
| Two-step login with the authenticator app on a real phone | Works |
