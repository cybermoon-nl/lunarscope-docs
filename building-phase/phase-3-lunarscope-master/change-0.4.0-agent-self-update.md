# Change (0.4.0) — signed agent self-update

**Repos:** `lunarscope-agent` 0.4.0, `lunarscope-master` 0.4.0
**Date:** 2026-11-16
**Status:** Done — code, tests, mutation checks and an end-to-end test in a
container; not committed yet

## What it does

An admin opens **Settings → Agent updates**, sees which version each agent
runs, and presses **Update** (one agent) or **Update all**. Within 5 minutes
(the agent's next check-in) the agent downloads the new binary, checks it,
and restarts itself with it. Nothing has to be reinstalled.

## The choice: who may decide what the agents run

The agents run as their own user, but the binary is what systemd starts.
Whoever can replace it can run code on every monitored server. So the
master must **not** be able to do that on its own: a hacked master would
otherwise mean every server is hacked.

The user chose **"Signed, key offline"**:

- A release is signed on the developer's laptop with a private Ed25519 key
  (`update-signing.key`) that never goes to the master.
- The public key is **built into the agent** (`update-key.pub` in the agent
  repo, read with `include_str!`).
- The master only passes the signed offer on. It can choose *when* an agent
  updates, but not *what* it installs.
- An agent only installs a **newer** version, so a stolen old (signed)
  release can't be used to go back to a version with a known bug.

```text
laptop                               master                         agent machine
──────                               ──────                         ─────────────
update-keygen  (once)
  update-signing.key  (stays here)
  update-key.pub ──► agent repo, built in
cargo build --release
update-sign --key … lunarscope-agent
  └─ lunarscope-agent.sig ─────────► --agent-binary + .sig
                                     admin presses Update
                                     update_requested = 1
                                     GET /api/agent-config ◄──────── every 5 min
                                     {"update": {version, sha256, signature}} ──►
                                                                    newer? signed? download
                                     GET /downloads/lunarscope-agent ◄────
                                                                    SHA-256 matches signed one?
                                                                    stage in /var/lib/lunarscope-agent/update/
                                                                    exit 75
                                                                    systemd: ExecStartPre=+ apply-update (root)
                                                                      checks everything again, installs
                                                                    agent 0.4.1 starts
```

### What is signed

```text
lunarscope-agent update
version=0.4.1
sha256=<hex of the binary>
```

The version is part of the message, so a signature for 0.4.1 can't be
reused with the number 9.9.9 on it, and the hash ties it to exactly one
binary. `<binary>.sig` is JSON:

```json
{ "version": "0.4.1", "sha256": "a4d3…", "signature": "9470…" }
```

### Two checks, the second one as root

1. The **agent** (user `lunarscope`, sandboxed) checks the offer before
   downloading (only newer versions, only with a key built in), then checks
   the download (signature, SHA-256, at most 64 MiB) and stages it in its
   state folder. It exits with code **75**.
2. systemd starts it again (`Restart=on-failure`). Before that,
   **`apply-update`** runs as root (`ExecStartPre=+`). It reads the staged
   binary **once**, checks those bytes again with the key built into the
   *installed* binary, and only then writes them to
   `/usr/local/bin/lunarscope-agent` (new file, `fsync`, `rename`, mode 755).
   The staged files are removed in every case.

The second check matters because the state folder belongs to the agent
user: if that user were taken over, it could swap the staged file. Root
doesn't trust what the agent user left behind.

`apply-update` **never fails the start**: if the update is refused, it logs
why and the installed agent starts as before.

## Agent

| File | Change |
|------|--------|
| `src/update.rs` (new) | `UpdateOffer`; `parse_version`, `is_newer`; `built_in_key()` (first non-comment line of `update-key.pub`; none = updates off); `check()` (newer, signature with `verify_strict`, size, SHA-256); `stage()`; `apply()`; `keygen()` (private key mode 600, refuses to overwrite); `sign()` (writes `<binary>.sig`) |
| `src/main.rs` | Commands: `--version`, `apply-update [--state-dir] [--target]`, `update-keygen <dir>`, `update-sign --key <file> [--version x.y.z] <binary>` (version defaults to the agent's own). `try_update()`; new `Wake::Update` when the offer in the configuration changes (no scan for that); `Outcome::Updated` → exit code 75. State folder from `$STATE_DIRECTORY` (systemd), else `/var/lib/lunarscope-agent` |
| `src/remote.rs` | `RemoteConfig.update: Option<UpdateOffer>` |
| `src/sender.rs` | `download_agent()`: `GET /downloads/lunarscope-agent`, 300 s timeout, stops above 64 MiB |
| `update-key.pub` (new) | The public key. In the repo it holds only a comment: updates stay off until you make your own key (below) |
| `lunarscope-agent.service` | `StateDirectory=lunarscope-agent` (mode 700), `ExecStartPre=+/usr/local/bin/lunarscope-agent apply-update` |
| `Cargo.toml` | 0.4.0; `ed25519-dalek` 3.0.0, `sha2` 0.11.1, `getrandom` 0.4.3 |

Agent log of an update:

```text
the master offers version 0.4.1, downloading
update 0.4.1 checked and staged in /var/lib/lunarscope-agent/update/lunarscope-agent; restarting to install it
installed update: lunarscope-agent 0.4.1
lunarscope-agent 0.4.1 started, master …
```

## Master

| File | Change |
|------|--------|
| `migrations/0004_users_settings_updates.sql` | `agents.agent_version`, `agents.update_requested` |
| `src/updates.rs` (new) | `UpdateOffer`, `is_newer` (unknown version counts as older), `agent_version()` from the User-Agent `lunarscope-agent/x.y.z`, `load_offer()`: reads `<--agent-binary>.sig`, refuses one made for another binary |
| `src/routes/install.rs` | `AgentBinary.offer` |
| `src/routes/api.rs` | `GET /api/agent-config` records the agent's version and adds `"update"` only when Update was pressed **and** the offer is newer than what the agent runs; once it runs that version (or newer) the request is cleared |
| `src/db/queries.rs` | `agent_config` stores the version (`COALESCE`: an unknown User-Agent keeps the old one); `request_update`, `clear_update_request`, `agent_updates` |
| `src/routes/updates.rs` (new) + `templates/updates.html` | Settings tab **Agent updates**: version, status (Up to date / Older version / Update requested), last check-in, **Update** per agent, **Update all (n)**. Both write an audit line. Admins only. Without a `.sig` the page says how to sign and offers no buttons (409 on POST) |
| `src/main.rs` | Routes; startup log says `signed update 0.4.1` or `no signed update (no .sig next to it)` |
| `install/lunarscope-agent.service` | Same unit changes as the agent repo |
| `scripts/install-dev-service.sh` | Also copies `lunarscope-agent.sig` (or removes an old one) on every restart |
| `scripts/demo-agents.sh` | The containers have no systemd: a small loop does its job (`apply-update` as root, then the agent, start again on exit) |

The master doesn't check the signature itself (it has no reason to hold
the key); it only checks that the `.sig` belongs to the binary, so a
forgotten re-sign shows at startup instead of at every agent.

## How to make a release (your laptop)

Once, make your key pair and build it into the agent:

```bash
cd lunarscope-agent
./target/release/lunarscope-agent update-keygen ~/.config/lunarscope
cp ~/.config/lunarscope/update-key.pub update-key.pub
```

Keep `~/.config/lunarscope/update-signing.key` safe and **never** copy it to
the master. Agents built before this step (and agents built from a repo
without a key) refuse all updates, so they need one normal reinstall with
an agent that has the key.

For every release: raise `version` in `Cargo.toml`, then

```bash
cargo build --release
./target/release/lunarscope-agent update-sign --key ~/.config/lunarscope/update-signing.key target/release/lunarscope-agent
sudo systemctl restart lunarscope
```

and press **Update all** under Settings → Agent updates.

## Tests

Agent **77** (+13), master **269** (+11).

| Test | Checks |
|------|--------|
| agent `update::versions` | Numbers, not text (`0.10.0` > `0.9.9`), equal is not newer |
| agent `keygen_makes_a_private_file_and_refuses_to_overwrite` | Mode 600, public key written, second keygen refused |
| agent `a_signed_newer_binary_passes` | Sign → check OK; `.sig` content |
| agent `anything_else_is_refused` | Not newer, other bytes, other version with the same signature, other hash, other key, too large, garbage signature |
| agent `staged_update_is_installed_by_apply` | Nothing staged → nothing; staged → installed, mode 755, staged files gone |
| agent `apply_refuses_a_tampered_staged_binary_and_cleans_up` | Staged file swapped after staging → refused, target unchanged, cleaned up |
| agent `built_in_key_file_is_read` | Comments skipped; no key = updates off |
| agent `a_new_update_offer_wakes_the_agent_without_a_scan` | New offer → `Wake::Update`; same offer again → nothing (no download every 5 minutes) |
| agent `offers_that_are_not_newer_are_not_downloaded` | Same/older version, or no key → no request to the master |
| agent `a_download_that_does_not_match_the_signature_is_not_staged` | Download happens, check fails, not staged |
| agent `the_binary_is_downloaded_from_the_master` | Request line; 404 is an error |
| agent `subcommands`, `apply_update_never_fails_the_service_start` | Command line; exit code 0 |
| master `updates::versions`, `version_from_user_agent`, `signature_file_must_belong_to_the_binary` | Version rules, User-Agent parsing (no other text), `.sig` checks |
| master `update_is_offered_only_after_update_was_pressed_and_only_if_newer` | No offer before Update; offer after; config version unchanged; cleared once 0.5.0 runs |
| master `no_downgrade_and_no_offer_without_a_signed_binary` | Agent on 0.6.0 gets nothing and the request is cleared; no `.sig` → no offer |
| master `an_unknown_user_agent_keeps_the_recorded_version` | `curl/…` doesn't wipe the version; an agent without version is offered the update |
| master `status_per_agent`, `page_lists_versions_with_a_button_for_older_agents`, `update_marks_one_agent_or_all`, `without_a_signed_binary_nothing_can_be_requested`, `read_only_users_cannot_see_or_press_update` | Page, buttons, audit line, 409 without `.sig`, 403 for read-only users |

| Check | Agent | Master |
|-------|-------|--------|
| `cargo test --locked` | ✅ 77 | ✅ 269 |
| `cargo clippy --all-targets --all-features --locked -- -D warnings` | ✅ | ✅ |
| `cargo fmt --check` | ✅ | ✅ |

### Mutation checks

| Deliberate bug | Caught by |
|----------------|-----------|
| Agent: "newer" also for the same version (`>=`) | 2 tests |
| Agent: no version check in `check()` | `anything_else_is_refused` |
| Agent: no SHA-256 check | 2 tests |
| Agent: staged files kept | 2 tests |
| Agent: private key readable by others (644) | `keygen_makes_a_private_file_and_refuses_to_overwrite` |
| Agent: no size limit | `anything_else_is_refused` (after adding the "too large" case) |
| Agent: version not in the signed message | 4 tests |
| Agent: the same offer wakes it every 5 minutes | `a_new_update_offer_wakes_the_agent_without_a_scan` |
| Agent: downloads offers that aren't newer | `offers_that_are_not_newer_are_not_downloaded` (after letting tests pass in a key) |
| Master: "newer" also for the same version | 4 tests |
| Master: `.sig` of another binary accepted | `signature_file_must_belong_to_the_binary` |
| Master: unknown User-Agent wipes the version | `an_unknown_user_agent_keeps_the_recorded_version` |
| Master: request never cleared | 2 tests |
| Master: up-to-date agent shown as older | 2 tests |
| Master: offered without pressing Update | `update_is_offered_only_after_update_was_pressed_and_only_if_newer` |
| Master: any User-Agent accepted as version | `version_from_user_agent` |

16 of 16 caught. In the first run 2 got through: the size limit had no test
yet, and `try_update` read the built-in key itself, so a test couldn't tell
"not newer" from "no key". `try_update` now gets the key as a parameter;
both have tests now.

## End-to-end test

On the laptop, without touching the `lunarscope` service or the demo
containers: a **test key** (in the scratch folder, not your key), two
release builds of a copy of the agent repo with that key built in (0.4.0
and 0.4.1), 0.4.1 signed. A temporary master on `127.0.0.1:3031`, one
`ubuntu:24.04` container `upd-test-01` added through "Add agent" and run
with the systemd stand-in loop.

1. Master with the 0.4.0 binary, no `.sig`: page says "No signed update",
   agent listed as `0.4.0 Up to date`.
2. Master restarted with 0.4.1 + `.sig`: log `signed update 0.4.1`; page
   shows `Older version`, **Update all (1)**. **Update** → 303, status
   `Update requested, at the next check-in`.
3. At the next check-in (under 5 minutes):

   ```text
   the master offers version 0.4.1, downloading
   update 0.4.1 checked and staged in /var/lib/lunarscope-agent/update/lunarscope-agent; restarting to install it
   agent exited with 75, starting it again in 10 s
   installed update: lunarscope-agent 0.4.1
   lunarscope-agent 0.4.1 started, master http://127.0.0.1:3031
   ```

   `lunarscope-agent --version` → 0.4.1, update folder empty, page shows
   `0.4.1 Up to date`.
4. **Attack:** master restarted with a binary signed as 0.4.2 by **another**
   key (what someone with control over the master could make). Update all →
   agent: `update 0.4.2 not installed: the signature doesn't match the
   built-in update key`; still 0.4.1, nothing staged.

The test master and container were removed afterwards.

## Limits

- Agents older than 0.4.0 don't report a version and can't update
  themselves: reinstall them once (new install link).
- An agent built without a key in `update-key.pub` never updates itself.
- If the private key is lost, make a new pair and reinstall the agents
  once. If it is **stolen**, do the same: the old key stays trusted by
  agents that have it until they're reinstalled.
- The signature proves the release came from your key, not that the code is
  good: CI (tests, cargo-deny) still runs before you sign.
