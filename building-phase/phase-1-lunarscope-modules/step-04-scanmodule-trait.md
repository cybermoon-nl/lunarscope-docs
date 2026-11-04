# Step 4 — `ScanModule` trait

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done

## Goal

Define the central contract of the modular architecture: a trait every scan
module implements, so the agent can run any module without knowing its
concrete type.

## What was done

Added to `src/lib.rs`:

```rust
/// Contract every scan module implements. The agent only talks to modules
/// through this trait, so modules can be added or removed without changing
/// the agent.
pub trait ScanModule: Send + Sync {
    /// Name used in `config.toml` to enable the module, e.g. `"ssh_scan"`.
    fn name(&self) -> &str;
    /// Short explanation of what the module checks.
    fn description(&self) -> &str;
    /// Runs all checks of the module and returns one finding per check.
    fn run(&self) -> Vec<Finding>;
}
```

## Choices and justification

- **Strategy pattern via a trait** — as decided in the architecture document
  (ADR on scan modules). The agent holds a `Vec<Box<dyn ScanModule>>` and calls
  `run()` on each; a new check is a new struct implementing this trait,
  registered in `modules/mod.rs` and enabled in `config.toml`. Rejected
  alternatives in the ADR were a scripting engine (bigger binary, larger
  attack surface) and hardcoded checks (not extendable).
- **`Send + Sync` supertraits** — the agent runs the scan loop inside a tokio
  runtime (step 17). Requiring both bounds on the trait itself means every
  `Box<dyn ScanModule>` can be moved to or shared between threads/tasks
  without extra wrapping. Modules are stateless unit structs, so the bound
  costs nothing in practice.
- **Object safe** — all methods take `&self` and have no generic parameters,
  so the trait can be used as `dyn ScanModule`. This is required for the
  module registry (`get_enabled_modules() -> Vec<Box<dyn ScanModule>>`,
  step 14).
- **`name()` returns `&str`** — it is compared against the strings in
  `modules.enabled` from `config.toml`, so it must match those exactly
  (`"ssh_scan"`, `"firewall_scan"`, `"package_scan"`).
- **`run()` returns `Vec<Finding>`, not `Result`** — a module never aborts the
  scan. If a check cannot be performed (e.g. `sshd_config` is unreadable),
  the module reports that as a finding itself. This keeps one broken module
  from hiding the results of the others, and the master sees *why* a check
  failed instead of silently missing data.

## Verification

```text
$ cargo build
    Finished `dev` profile [unoptimized + debuginfo] target(s)

$ cargo clippy -- -D warnings
    Finished `dev` profile [unoptimized + debuginfo] target(s)
```

A temporary example (removed afterwards) implemented a dummy module, stored it
as `Vec<Box<dyn ScanModule>>`, moved that vector into a new thread and ran it
there. This compiles only if the trait is object safe and `Send`:

```text
[Finding { check_name: "dummy", severity: Pass, description: "ok", remediation: None }]
```

## Tests (added after step 10, 2026-10-17)

The temporary example above was replaced by permanent tests. A review found
a gap: before these tests, **removing `Send + Sync` from the trait did not
break any test**. The old integration test created the modules *inside* the
spawned thread, so nothing actually crossed a thread boundary.

In `src/lib.rs`:

| Test | Checks |
|------|--------|
| `scan_module_trait_objects_are_send_and_sync` | Compile-time check that `dyn ScanModule`, `Box<dyn ScanModule>` and `Vec<Box<dyn ScanModule>>` are `Send + Sync` |

The check uses a helper that only compiles for thread-safe types:

```rust
fn assert_send_sync<T: Send + Sync + ?Sized>() {}

assert_send_sync::<dyn ScanModule>();
```

In `tests/public_api.rs`:

| Test | Checks |
|------|--------|
| `modules_are_moved_and_shared_between_threads` | `all_modules()` is created on the test thread, wrapped in an `Arc` and run by **4 threads at the same time**; all threads must return the same checks (no shared state between runs) |
| `findings_can_be_sent_back_from_a_thread` | A `Box<dyn ScanModule>` is moved into a thread and its `Vec<Finding>` is returned to the caller |
| `external_module_works_next_to_built_in_modules` | A `DummyScan` defined **outside** the library implements `ScanModule`, is added to `all_modules()`, is selected by name with a config-style filter together with `firewall_scan`, and both run. This shows the "add a module" path from the architecture document and that the trait is object safe |
| `modules_can_be_filtered_on_config_names` | (step 8) filtering on `name()` like `get_enabled_modules()` |

Every module also has a `name_matches_config_key` test (steps 5–7) that
checks `name()` and that `description()` is not empty.

**Mutation check** — the bound was removed from the trait in three ways:

| Bug introduced | Result |
|----------------|--------|
| `pub trait ScanModule {` (no `Send + Sync`) | test build fails: "`dyn ScanModule` cannot be sent between threads safely" and "... cannot be shared between threads safely" — in `src/lib.rs` **and** `tests/public_api.rs` |
| `pub trait ScanModule: Send {` | fails: "cannot be shared between threads safely" |
| `pub trait ScanModule: Sync {` | fails: "cannot be sent between threads safely" |

A compile error counts as a failing test: `cargo test` (and the CI test job)
stops with an error.

## Next step

Step 5 — first module: `ssh_scan`.
