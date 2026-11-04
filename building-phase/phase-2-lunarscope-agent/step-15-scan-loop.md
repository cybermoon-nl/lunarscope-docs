# Step 15 — Scan loop (sync, no timer)

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

## Goal

Get the modules → loop over them → call `run()` → collect all findings into
one list.

## What was done

```rust
fn scan(modules: &[Box<dyn ScanModule>]) -> Vec<ScanResult> {
    let mut results = Vec::new();
    for module in modules {
        let findings = panic::catch_unwind(AssertUnwindSafe(|| module.run()))
            .unwrap_or_else(|_| {
                eprintln!("module '{}' panicked", module.name());
                vec![/* Low finding "<module>_crashed" with remediation */]
            });
        results.extend(findings.into_iter().map(|finding| ScanResult {
            scan_type: module.name().to_string(),
            finding,
        }));
    }
    results
}
```

`ScanResult` (in `src/sender.rs`):

```rust
pub struct ScanResult {
    pub scan_type: String,  // module name, e.g. "ssh_scan"
    pub finding: Finding,
}
```

## Choices and justification

- **`Vec<ScanResult>` instead of `Vec<Finding>`** — the guide collects into one
  `Vec<Finding>`. But the API (architecture document 5.2) and the
  `scan_results` table both need **`scan_type`**, the name of the module that
  produced the finding, and `Finding` doesn't contain it. A plain
  `Vec<Finding>` would lose that information. `ScanResult` keeps each finding
  together with its module name. The library's `Finding` type stays
  unchanged, so no new library release is needed.
- **A panicking module doesn't stop the agent** — modules are supposed to never
  panic (step 4: they report problems as findings). If a future module has a
  bug anyway, `catch_unwind` turns the panic into a Low finding
  `<module>_crashed`, the other modules still run, and the dashboard shows the
  problem. This is also why the release profile keeps `panic = "unwind"` and
  doesn't use `panic = "abort"` (step 19).
- **Synchronous, on the tokio thread** — modules do blocking work (file reads,
  `systemctl`, `apt-get`). The agent has nothing else to do while scanning, so
  running them directly on the single runtime thread is simpler than
  `spawn_blocking`, and it adds no extra threads (step 19 shows one thread).

## Checks — unit tests (`src/main.rs`)

| Test | Checks |
|------|--------|
| `scan_collects_findings_of_all_modules_with_scan_type` | Two test modules × two findings → 4 results, in order, all with `scan_type` |
| `panicking_module_becomes_a_finding_and_others_still_run` | A module that panics gives one Low `broken_scan_crashed` finding with remediation, and the next module still runs |
| `scan_with_real_modules_tags_every_finding` | With the real three modules, each module name appears as `scan_type` |

Mutation check: replacing `catch_unwind` with a direct `module.run()` →
`panicking_module_becomes_a_finding_and_others_still_run` fails (the panic
reaches the test).

## Next step

Step 16 — HTTP POST to the master.
