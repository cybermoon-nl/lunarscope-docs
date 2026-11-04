# Step 27 — Agent registration endpoint

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

`POST /api/register-agent` that creates a new record in `agents` and returns
the generated API key.

## What was done

### Request and answer

```http
POST /api/register-agent
Authorization: Bearer <admin token>
Content-Type: application/json

{"hostname": "web-01"}
```

```http
HTTP/1.1 201 Created
Content-Type: application/json

{"agent_id": "3f2c…-4…", "hostname": "web-01", "api_key": "lsk_<64 hex characters>"}
```

The admin copies `agent_id` and `api_key` into the agent's
`/etc/lunarscope/config.toml` (agent step 13). The key is shown **only in
this answer**; the master stores just its SHA-256 hash (step 25), so a lost
key can't be recovered, only replaced by registering again.

| Status | When |
|--------|------|
| 201 | Agent created |
| 400 | Body not JSON, `hostname` missing/not a string/blank/longer than 255 |
| 401 | Admin token missing or wrong (also: an agent's API key) |
| 403 | Registration disabled: master started without `--admin-token-file` |
| 413 | Body > 64 KiB |
| 500 | Database or random generator error |

### Files

| File | Change |
|------|--------|
| `src/routes/api.rs` | `register_agent` handler, `RegisterRequest`/`RegisterResponse`, shared `json_rejection()`/`check_text()` helpers, 11 tests |
| `src/auth.rs` | `Admin` extractor, `load_admin_token()`, `constant_time_eq()`, `generate_api_key()`, 6 tests |
| `src/db/queries.rs` | `insert_agent()` |
| `src/main.rs` | `--admin-token-file` argument, `AppState::admin_token_hash`, `AppState::new()`, route, 1 test |
| `Cargo.toml` | `getrandom = "0.4.3"`, `uuid = { version = "1.29.0", default-features = false, features = ["v4"] }` |

### New startup option

```bash
openssl rand -hex 32 | sudo tee /etc/lunarscope/admin-token >/dev/null
sudo chown root:lunarscope /etc/lunarscope/admin-token
sudo chmod 640 /etc/lunarscope/admin-token
lunarscope-master --db /var/lib/lunarscope/master.db --admin-token-file /etc/lunarscope/admin-token
```

Startup log:
`… ready, 0 registered agent(s), agent registration enabled`
(or `disabled (no --admin-token-file)`).

## Choices and justification

### The endpoint is protected with an admin token

The guide doesn't say who may call this endpoint. Left open, **anyone on the
internet** could register agents. They would get valid API keys, write
findings into the database and fill it up, since there is no retention. The
endpoint therefore needs authentication, but of a different kind than the
agents use:

- **A separate admin token**, read from a file at startup
  (`--admin-token-file`), stored in memory only as its SHA-256 hash. An agent's
  API key is **not** accepted as an admin token, and the admin token is not
  accepted as an agent key (both are tested). A compromised server can't
  register more agents.
- **No token file → registration disabled (403)** with a message saying how
  to enable it. A master that is started without configuration is safe by
  default. The admin can also leave it disabled and only enable it while
  adding servers.
- **At least 64 characters** (`openssl rand -hex 32` = 256 bits); shorter
  tokens stop the master at startup. A warning is shown if the file is
  readable by every user.
- **A file, not an environment variable or a command-line value** —
  environment variables and arguments are visible in `systemctl show` and
  `ps`. A file can be restricted to `root:lunarscope 640`.
- **Constant-time comparison** of the hashes, so the response time doesn't
  reveal how much of a guessed token was right.
- Rejected alternative: "only accept registrations from `127.0.0.1`". It is
  simpler, but behind a reverse proxy on the same machine (one option for
  HTTPS in step 32) **every** request comes from `127.0.0.1`, which would
  silently open the endpoint to everyone.

### The master generates the agent id

The architecture document (4.2) describes the id as "given by the agent
itself". Here the **master** generates a random **UUID v4** and returns it with
the key, because:

- the agent can't register itself anyway (it needs the admin token), so the
  admin already does the registration by hand;
- the master can be sure ids are unique and well-formed. With ids chosen by
  the client, it would have to validate the format and handle duplicates.

The agent's config already has an `agent_id` field (agent step 12), so the
agent needs no change.

### Key format: `lsk_` + 64 hex characters

- **256 bits from the operating system's secure random generator**
  (`getrandom`, i.e. the Linux `getrandom()` system call), as required by the
  architecture document (5.3: "cryptographic random strings, minimum 256
  bits"). Not `rand`'s general-purpose generators, and not derived from time
  or ids.
- **Hex** — only `[0-9a-f]`, so it is safe in TOML, shell commands and HTTP
  headers without escaping.
- **`lsk_` prefix** ("lunarscope key") — makes a leaked key recognisable, e.g.
  in a log or a commit. Secret scanners such as gitleaks (phase 4) can match
  `lsk_[0-9a-f]{64}` with a custom rule.

### Shared helpers

Both API handlers now use the same `json_rejection()` (413 vs 400) and
`check_text()` (blank / too long). The 17 scan-result tests confirm the
refactoring didn't change that endpoint's behaviour.

## Checks — unit tests

### `register_tests` in `src/routes/api.rs`

| Test | Checks |
|------|--------|
| `registration_returns_id_and_key_and_stores_only_the_hash` | 201; id is a UUID **v4**; key `lsk_` + 64 chars; row has the hostname, `SHA-256(key)` (not the key), `created_at` ≈ now, `last_seen` NULL |
| `registered_key_can_send_scan_results` | The returned id + key are accepted by `POST /api/scan-result` (200, stored) — registration and reporting work together |
| `every_registration_gets_a_new_id_and_key` | Same hostname twice → two agents, different ids and keys |
| `hostname_is_trimmed` | `"  web-01 \n"` → `web-01` |
| `missing_or_wrong_admin_token_is_401` | No header, wrong token, token without `Bearer`, the token's **hash** used as token → 401, nothing stored |
| `an_agent_key_is_not_an_admin_token` | A registered agent's key can't register agents |
| `admin_token_is_not_an_agent_key` | The admin token can't send scan results |
| `registration_without_admin_token_configured_is_403` | No `--admin-token-file` → 403 with a hint |
| `invalid_bodies_are_400` | Broken JSON, `{}`, empty/blank/number/256-char hostname → 400, nothing stored |
| `admin_token_is_checked_before_the_body` | Wrong token + broken JSON → 401 |
| `database_failure_is_500` | Closed pool → 500 "internal server error" |

### New in `src/auth.rs` and `src/main.rs`

| Test | Checks |
|------|--------|
| `generated_keys_have_prefix_and_256_bits_of_hex` | `lsk_` + 64 lowercase hex |
| `generated_keys_are_unique` | 1000 keys, no duplicates |
| `constant_time_eq_compares_whole_strings` | Equal, differing first/last byte, different lengths, empty |
| `admin_token_file_is_read_trimmed_and_hashed` | `"  <token>\n"` → hash of `<token>` |
| `short_admin_token_is_refused` | 9 characters → error mentioning the minimum of 64 |
| `missing_admin_token_file_is_an_error` | Error contains the path |
| `admin_token_file_is_optional` (main) | Default `None`; `--admin-token-file <path>`; missing path → error |

Total master tests: **72** (54 + 18 new), all passing.

### Mutation checks

| Bug introduced | Failing tests |
|----------------|---------------|
| admin token not compared (always accepted) | `missing_or_wrong_admin_token_is_401`, `an_agent_key_is_not_an_admin_token`, `admin_token_is_checked_before_the_body` |
| registration allowed when no token is configured | `registration_without_admin_token_configured_is_403` |
| `constant_time_eq` ignores the length | `constant_time_eq_compares_whole_strings` |
| plain key stored instead of its hash | `registration_returns_id_and_key_and_stores_only_the_hash`, `registered_key_can_send_scan_results` |
| only 8 random bytes (64-bit keys) | `generated_keys_have_prefix_and_256_bits_of_hex`, `registration_returns_id_and_key_and_stores_only_the_hash` |
| key bytes not filled from `getrandom` (all zero) | `generated_keys_are_unique`, `every_registration_gets_a_new_id_and_key` |
| hostname not validated | `invalid_bodies_are_400` |
| short admin token accepted | `short_admin_token_is_refused` |

### Running the binary

```text
$ lunarscope-master --db ./m.db
… ready, 0 registered agent(s), agent registration disabled (no --admin-token-file)

$ lunarscope-master --db ./m.db --admin-token-file ./admin-token     # openssl rand -hex 32, mode 600
… ready, 0 registered agent(s), agent registration enabled

$ lunarscope-master --db ./m.db --admin-token-file ./short           # "short"
lunarscope-master: admin token in ./short is 5 characters; at least 64 are required (create one with 'openssl rand -hex 32')
exit=1

$ lunarscope-master --db ./m.db --admin-token-file ./open            # mode 644
warning: ./open is readable by every user; run 'chmod 600' on it
… agent registration enabled

$ lunarscope-master --db ./m.db --admin-token-file ./nope
lunarscope-master: could not read admin token ./nope: No such file or directory (os error 2)
exit=1
```

```text
$ cargo test                                → 72 passed, 0 failed
$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

Calling the endpoint with `curl` follows once the master listens on a port
(step 32), in the end-to-end test (step 33).

## Next step

Step 28 — Tera templates (`base.html` with navbar + HTMX, `dashboard.html`).
