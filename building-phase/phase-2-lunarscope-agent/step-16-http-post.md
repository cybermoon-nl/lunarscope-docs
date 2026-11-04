# Step 16 — HTTP POST to the master

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

## Goal

Build the JSON payload and send it with reqwest as `POST /api/scan-result`,
with an `Authorization: Bearer <key>` header and a Unix timestamp in the body.
Log the HTTP status code.

## What was done

New file `src/sender.rs` with `Reporter`:

| Item | Responsibility |
|------|----------------|
| `Reporter::new(config, hostname)` | Builds the endpoint `<master_url>/api/scan-result` and the HTTP client |
| `Reporter::send_all(results)` | One request per finding; returns a `SendSummary` |
| `send(result)` | A single POST with headers and body |
| `payload_json(...)` | Serialises the body |
| `unix_timestamp()` | Seconds since 1970, taken right before each request |
| `error_chain(err)` | Error message including its causes, for the logs |

### Request

```http
POST /api/scan-result HTTP/1.1
Authorization: Bearer <api_key>
Content-Type: application/json
User-Agent: lunarscope-agent/0.1.0

{"agent_id":"550e8400-e29b-41d4-a716-446655440000","hostname":"web-01",
 "scan_type":"ssh_scan","check_name":"ssh_permit_root_login","severity":"High",
 "description":"Root can log in","remediation":"Set PermitRootLogin no",
 "timestamp":1791072132}
```

The fields are exactly those of the architecture document (5.2). The finding's
own fields are merged into the top level with `#[serde(flatten)]`:

```rust
#[derive(Serialize)]
struct Payload<'a> {
    agent_id: &'a str,
    hostname: &'a str,
    scan_type: &'a str,
    #[serde(flatten)]
    finding: &'a Finding,
    timestamp: u64,
}
```

`hostname` is read from `/proc/sys/kernel/hostname` (falls back to `"unknown"`).

### HTTP client settings

| Setting | Value | Why |
|---------|-------|-----|
| `tls_version_min` | TLS 1.3 | Architecture document 5.5: only TLS 1.3 |
| Certificate check | OS trust store (`rustls-platform-verifier`) | Let's Encrypt certificate on the master is trusted through `ca-certificates`; self-signed/unknown CAs are refused |
| `timeout` / `connect_timeout` | 10 s / 5 s | A hanging master can't block the agent forever |
| `user_agent` | `lunarscope-agent/<version>` | Lets the master log/identify agent versions |

### Status handling and logging

| Response | Behaviour |
|----------|-----------|
| 2xx | counted as accepted |
| **401** | log "master rejected the API key (401 Unauthorized); check api_key and agent_id" and **stop this cycle**: every other request would fail the same way |
| other status (400, 500, …) | log `master answered <status> for <scan_type>/<check_name>`; continue with the next finding |
| network/TLS error | log `could not reach master at <url>: <error chain>` and **stop this cycle** |

After each cycle the agent logs one summary line:
`scan cycle: 5 finding(s) in 1227 ms; accepted 5, rejected 0, not sent 0`.

## Choices and justification

- **One request per finding** — as specified in the architecture document
  (2.3, 3.1.3) and as the master's handler is designed (step 25: "write the
  finding to `scan_results`"). It keeps the master simple: one row per request.
- **Timestamp per request, not per scan** — the master rejects timestamps more
  than 60 s off (replay protection). Taking the time right before each request
  keeps all requests valid even if sending a long list takes a while.
- **Body serialised with `serde_json::to_vec`** — reqwest's `json` feature is
  not needed; fewer features.
- **The API key is never logged.**
- **`error_chain`** — reqwest's top-level error text is only "error sending
  request for url (…)". The useful part ("Connection refused",
  "invalid peer certificate: UnknownIssuer", "ProtocolVersion") is in the
  error's causes, so they are appended once each.

## Checks

### Unit tests (`src/sender.rs`)

The tests use a small fake HTTP server (std `TcpListener` on `127.0.0.1:0` in a
thread). It records each request and answers with a configured status, so no
extra test dependency is needed.

| Test | Checks |
|------|--------|
| `payload_matches_api_specification` | Body is exactly the 8 fields of the API spec, with the right values |
| `payload_without_remediation_has_null` | `remediation: null`, `severity: "Pass"` |
| `timestamp_is_current_unix_time` | Seconds (not milliseconds), after 2025-01-01 |
| `endpoint_is_built_from_base_url` | Trailing slash / extra path in `master_url` still gives `/api/scan-result` |
| `sends_one_authenticated_post_per_finding` | 2 findings → 2 POSTs to `/api/scan-result` with `Bearer test-key`, `application/json`, user agent, body fields, timestamp within 5 s |
| `unauthorized_stops_the_cycle` | 401 on the first of 3 → 1 request made, 2 skipped |
| `other_error_status_skips_only_that_finding` | 500, 400, 200 → all 3 sent, 1 accepted, 2 rejected |
| `unreachable_master_aborts_without_panicking` | Closed port → nothing accepted, cycle aborted, reason contains "refused" |
| `error_chain_includes_causes_once` | Causes appended in order; repeated text not duplicated |
| `empty_cycle_sends_nothing` | No findings → no requests |

Mutation checks:

| Bug introduced | Failing tests |
|----------------|---------------|
| `Authorization: <key>` without `Bearer ` | `sends_one_authenticated_post_per_finding` |
| 401 doesn't stop the cycle | `unauthorized_stops_the_cycle` |
| `#[serde(flatten)]` removed (finding nested) | `payload_matches_api_specification`, `payload_without_remediation_has_null`, `sends_one_authenticated_post_per_finding` |
| Timestamp in milliseconds | `timestamp_is_current_unix_time` |

### Manual run against a fake master

A small Python fake master (it checks the Bearer key and the 60 s window,
and logs each request) received a `--once` run on the dev machine:

```text
200 /api/scan-result age 0 ssh_scan ssh_config_readable Low fedora
200 /api/scan-result age 0 firewall_scan firewall_ufw_active High fedora
200 /api/scan-result age 0 package_scan package_updates_checkable Low fedora
```

With a wrong key: `master rejected the API key (401 Unauthorized)…`,
`accepted 0, rejected 1, not sent 2`, exit code 2.

### TLS checks

The agent was run against a local HTTPS fake master with a certificate for
`localhost` from a throw-away test CA
([evidence](evidence/step-16-tls-checks.txt)):

| Server | Result |
|--------|--------|
| TLS 1.3, CA **not** trusted | refused: `invalid peer certificate: UnknownIssuer`, 0 requests |
| **TLS 1.2 only**, CA trusted (`SSL_CERT_FILE`) | refused: `received fatal alert: ProtocolVersion`, 0 requests |
| TLS 1.3, CA trusted | 3 findings accepted |

So the agent verifies certificates and enforces TLS 1.3.

## Next step

Step 17 — interval timer.
