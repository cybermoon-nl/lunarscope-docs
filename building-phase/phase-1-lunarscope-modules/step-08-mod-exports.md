# Step 8 — `mod.rs` + public exports

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done

## Goal

Finish `src/modules/mod.rs` with `pub mod ssh_scan; pub mod firewall_scan;
pub mod package_scan;` and re-export everything via `src/lib.rs`, so the
agent can use the modules with short paths.

## What was done

The three `pub mod` lines were already added one by one in steps 5–7 (needed
to compile each module). This step added the exports and a module registry.

### `src/modules/mod.rs`

```rust
pub mod firewall_scan;
pub mod package_scan;
pub mod ssh_scan;

pub use firewall_scan::FirewallScan;
pub use package_scan::PackageScan;
pub use ssh_scan::SshScan;

use crate::ScanModule;

/// Returns one instance of every available module. The agent filters this
/// list on the names enabled in `config.toml`.
pub fn all_modules() -> Vec<Box<dyn ScanModule>> {
    vec![
        Box::new(SshScan),
        Box::new(FirewallScan),
        Box::new(PackageScan),
    ]
}
```

Plus a doc comment at the top describing how to add a module, and a unit test
`all_modules_have_unique_names`.

### `src/lib.rs`

```rust
pub mod modules;

pub use modules::{FirewallScan, PackageScan, SshScan, all_modules};
```

### Public API after this step

| Path | Item |
|------|------|
| `lunarscope_modules::Severity` | enum (step 2) |
| `lunarscope_modules::Finding` | struct (step 3) |
| `lunarscope_modules::ScanModule` | trait (step 4) |
| `lunarscope_modules::{SshScan, FirewallScan, PackageScan}` | module structs (re-exported) |
| `lunarscope_modules::all_modules()` | registry of all modules |
| `lunarscope_modules::modules::{ssh_scan, firewall_scan, package_scan}` | the module files themselves (full paths still work) |

The agent can now write:

```rust
use lunarscope_modules::{all_modules, Finding, ScanModule};
```

## Choices and justification

- **Re-exports at two levels** — `modules` re-exports the structs and
  `lib.rs` re-exports them again. Users of the crate don't need to know the
  internal file layout (`lunarscope_modules::SshScan` instead of
  `lunarscope_modules::modules::ssh_scan::SshScan`). Files can later be
  moved or renamed without breaking the agent, as long as the re-exports
  stay the same.
- **Helper functions stay private** — only the structs are exported.
  `scan_config`, `evaluate`, `parse_upgrades` etc. are implementation details
  (tested inside their own files), so the public API stays small and they can
  change without a breaking release.
- **`all_modules()` added to the library (not in the guide)** — the
  architecture document says modules are registered in `modules/mod.rs`, and
  the ADR's goal is that a new check needs no changes to the agent. With
  the list of modules living in the library, adding a module means:
  1. create `src/modules/<name>.rs`,
  2. add `pub mod`, `pub use` and one `Box::new(...)` line in `mod.rs`,
  3. enable it in `config.toml` and bump the library version.

  The agent's `get_enabled_modules(config)` (step 14) then only has to
  *filter* `all_modules()` on `config.modules.enabled`. It doesn't need to
  know any concrete module types. Creating all three modules costs nothing:
  they are zero-sized unit structs, and only enabled modules have `run()`
  called.
- **Unique-name test** — `name()` is the key used in `config.toml`. If two
  modules had the same name, or a module was forgotten in `all_modules()`,
  the agent would silently run the wrong set. The test pins the exact list
  of names.

## Verification

### New tests

| Test | Type | Checks |
|------|------|--------|
| `modules::tests::all_modules_have_unique_names` | unit | `all_modules()` contains exactly `firewall_scan`, `package_scan`, `ssh_scan` |
| `module_structs_are_exported_at_crate_root_and_in_modules` | integration | Short and full paths both compile and refer to the same modules |
| `modules_can_be_filtered_on_config_names` | integration | Filtering `all_modules()` on `["ssh_scan", "package_scan"]` returns those two, as the agent will do |
| `every_module_runs_and_serialises` | integration | Each module returns ≥ 1 finding, and every finding serialises to JSON with all four fields. *(Originally named `every_module_runs_on_another_thread_and_serialises`; renamed after step 10 because it created the modules inside the thread and so did not really test `Send` — see step 4 for the real thread tests.)* |
| `shared_types_are_usable_from_outside` | integration | `Finding`/`Severity` can be built, cloned and debug-printed from outside the crate |

The integration tests are in `tests/public_api.rs`. Cargo compiles that file
as a **separate crate**, so it can only use what is really `pub`. If an
export is missing, it fails to compile — the same error the agent would get.

Mutation check: removing `Box::new(PackageScan)` from `all_modules()` makes
`all_modules_have_unique_names` fail.

### Results

```text
$ cargo test
     Running unittests src/lib.rs
test result: ok. 39 passed; 0 failed
     Running tests/public_api.rs
test result: ok. 4 passed; 0 failed

$ cargo clippy --all-targets -- -D warnings      → no warnings
$ cargo fmt --check                              → no changes
$ RUSTDOCFLAGS="-D warnings" cargo doc --no-deps → builds without warnings
```

`cargo doc` was added as a check because `mod.rs` now contains doc links
(`` [`ScanModule`] ``, `` [`all_modules`] ``), and a broken link would show up
as a warning.

## Next step

Step 9 — unit tests per module (review coverage of the tests written in
steps 5–8).
