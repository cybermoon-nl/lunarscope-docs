# Step 2 — `Severity` enum

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done

## Goal

Define the severity levels a scan finding can have, as a public enum in
`src/lib.rs` with `#[derive(Debug, Serialize, Clone)]`.

## What was done

Added to `src/lib.rs`:

```rust
use serde::Serialize;

/// How serious a finding is. `Pass` means the check found no problem.
#[derive(Debug, Serialize, Clone)]
pub enum Severity {
    Critical,
    High,
    Medium,
    Low,
    Pass,
}
```

## Choices and justification

- **Five levels, `Critical` → `Low` plus `Pass`** — follows the severity scale
  from the guide and the architecture document. `Pass` is included so a
  module can explicitly report that a check *succeeded*; this lets the
  dashboard show "checked and OK" instead of an empty list, which would be
  indistinguishable from "not checked".
- **`Debug`** — readable output in logs (`eprintln!("{:?}", finding)`) and in
  test assertion failures.
- **`Serialize`** — findings are sent as JSON from the agent to the master
  (`POST /api/scan-result`). Only `Serialize` is derived here because the
  library itself only *produces* findings; if the master needs to parse them
  into the same type, `Deserialize` can be added then.
- **`Clone`** — lets a finding (and its severity) be copied, e.g. when the
  agent collects all findings into one `Vec<Finding>` (step 15).
- **No `#[serde(rename_all = ...)]`** — serde's default serialises unit
  variants as their name, so the JSON values are `"Critical"`, `"High"`,
  `"Medium"`, `"Low"` and `"Pass"`. The master stores these strings as-is in
  `scan_results`. Keeping the default avoids a mismatch between the Rust name
  and the stored value.

## Verification

```text
$ cargo build
    Finished `dev` profile [unoptimized + debuginfo] target(s)

$ cargo clippy -- -D warnings
    Finished `dev` profile [unoptimized + debuginfo] target(s)
```

The JSON form was checked with a temporary example (removed afterwards, not
part of the repo) that serialised all variants with `serde_json::to_string`:

```text
["Critical","High","Medium","Low","Pass"]
```

This was turned into permanent unit tests afterwards (see below).

## Tests (added after step 10, 2026-10-17)

In `src/lib.rs`, `#[cfg(test)] mod tests`:

| Test | Checks |
|------|--------|
| `severity_serialises_as_variant_name` | `Serialize`: JSON is exactly `["Critical","High","Medium","Low","Pass"]`, the strings the master stores |
| `severity_debug_output_is_variant_name` | `Debug`: `{:?}` prints the variant name (used in agent logs); `Clone` gives an equal value |
| `shared_types_are_send_and_sync` | `Severity` is `Send + Sync` (compile-time check) |

In addition, every finding from every module goes through
`assert_valid_finding` (step 9), which checks that `severity` serialises to
one of the five strings.

**Mutation check** — the tests were confirmed to catch these bugs:

| Bug introduced | Result |
|----------------|--------|
| `#[serde(rename_all = "lowercase")]` on `Severity` | `severity_serialises_as_variant_name` and the `all_outcomes_are_valid_findings` / `run_returns_valid_findings` tests of all modules fail (9 tests) |
| Hand-written `Debug` that prints `Severity` instead of the variant | `severity_debug_output_is_variant_name` fails |

## Next step

Step 3 — `Finding` struct.
