# Step 3 — `Finding` struct

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done

## Goal

Define the data type every scan module returns: one `Finding` per checked
item, with the same derives as `Severity`.

## What was done

Added to `src/lib.rs`:

```rust
/// One result of a single check performed by a scan module.
#[derive(Debug, Serialize, Clone)]
pub struct Finding {
    /// Identifier of the check, e.g. `"ssh_permit_root_login"`.
    pub check_name: String,
    pub severity: Severity,
    /// Human-readable explanation of what was found.
    pub description: String,
    /// How to fix the problem; `None` when there is nothing to fix.
    pub remediation: Option<String>,
}
```

## Choices and justification

- **Public fields** — modules (step 5–7) construct findings directly with a
  struct literal and the agent/master read them. There are no invariants to
  protect between the fields, so a constructor or getters would only add code.
- **`String` instead of `&'static str`** — descriptions often contain runtime
  values (e.g. the actual `PermitRootLogin` value read from `sshd_config`, or
  package names from `apt-get`). Owned strings also keep the struct free of
  lifetimes, which makes it easy to move between threads (`ScanModule` is
  `Send + Sync`, step 4) and to collect into one `Vec<Finding>`.
- **`check_name` per finding, not per module** — one module performs several
  checks (`ssh_scan` checks both `PermitRootLogin` and
  `PasswordAuthentication`). A per-check identifier lets the dashboard group
  and compare results of the same check across servers and over time.
- **`remediation: Option<String>`** — a `Pass` finding has nothing to fix, so
  the field is optional instead of an empty string. In JSON it becomes `null`,
  which the master can store as `NULL` in `scan_results`.
- **Same derives as `Severity`** (`Debug`, `Serialize`, `Clone`) — `Finding`
  can only derive these because every field type implements them, which is
  also why `Severity` needed them in step 2.

## Verification

```text
$ cargo build
    Finished `dev` profile [unoptimized + debuginfo] target(s)

$ cargo clippy -- -D warnings
    Finished `dev` profile [unoptimized + debuginfo] target(s)
```

The JSON shape was checked with a temporary example (removed afterwards)
serialising a failing and a passing finding:

```json
[
  {
    "check_name": "ssh_permit_root_login",
    "severity": "High",
    "description": "PermitRootLogin is set to yes",
    "remediation": "Set PermitRootLogin no in /etc/ssh/sshd_config"
  },
  {
    "check_name": "ufw_active",
    "severity": "Pass",
    "description": "UFW is active",
    "remediation": null
  }
]
```

This is the shape the master's `POST /api/scan-result` handler (step 25)
will receive inside the payload.

## Tests (added after step 10, 2026-10-17)

In `src/lib.rs`:

| Test | Checks |
|------|--------|
| `finding_serialises_with_all_fields` | JSON has exactly the four fields (no more, no fewer); `remediation: None` becomes `null` |
| `finding_with_remediation_serialises_it_as_string` | `remediation: Some(..)` becomes a plain JSON string; severity is `"High"` |
| `cloned_finding_is_independent` | `Clone` makes a deep copy: changing the copy doesn't change the original |
| `shared_types_are_send_and_sync` | `Finding` and `Vec<Finding>` are `Send + Sync` (compile-time check) |

In `tests/public_api.rs` (separate crate, public API only):

| Test | Checks |
|------|--------|
| `shared_types_are_usable_from_outside` | All fields are `pub`: a `Finding` can be built, cloned and debug-printed from another crate |

**Mutation check:**

| Bug introduced | Result |
|----------------|--------|
| `#[serde(skip_serializing_if = "Option::is_none")]` on `remediation` (field disappears from JSON when `None`) | `finding_serialises_with_all_fields` fails |

## Next step

Step 4 — `ScanModule` trait.
