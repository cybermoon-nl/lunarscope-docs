# Step 1 — Repo + crate setup

**Repo:** `lunarscope-modules`
**Date:** 2026-10-17
**Status:** Done

## Goal

Turn the existing `lunarscope-modules` repository into a Rust library crate,
add `serde` + `serde_json` as dependencies and set the crate type to `rlib`.

## What was done

The repository already existed on GitHub (README + `.github/` with the CI
workflow and Dependabot config), so instead of `cargo new` (which creates a
new directory) the crate was initialised in place:

```bash
cd repos/lunarscope-modules
cargo init --lib --name lunarscope-modules
cargo add serde --features derive
cargo add serde_json
```

Afterwards the `[lib]` section was added to `Cargo.toml` and the generated
placeholder code (`add()` + test) in `src/lib.rs` was replaced by a crate-level
doc comment, because the real types follow in step 2–4.

### Resulting `Cargo.toml`

```toml
[package]
name = "lunarscope-modules"
version = "0.1.0"
edition = "2024"
description = "Shared scan modules for the Lunarscope agent and master node"

[lib]
crate-type = ["rlib"]

[dependencies]
serde = { version = "1.0.229", features = ["derive"] }
serde_json = "1.0.154"
```

### Files added to the repo

| File | Purpose |
|------|---------|
| `Cargo.toml` | Crate manifest |
| `Cargo.lock` | Locked dependency versions (reproducible builds, input for `cargo audit` in CI) |
| `.gitignore` | Ignores `/target` so build output is never committed |
| `src/lib.rs` | Library root (only a doc comment for now) |

## Choices and justification

- **`crate-type = ["rlib"]`** — the Rust library format, linked statically
  into the `lunarscope-agent` binary. No `cdylib`/`dylib` is needed because
  modules are compiled in (Strategy pattern via a trait, see the architecture
  document ADR on scan modules), not loaded at runtime. This keeps the agent
  a single self-contained binary.
- **`serde` with the `derive` feature** — needed for `#[derive(Serialize)]` on
  `Severity` and `Finding` (step 2–3), so findings can be sent as JSON to the
  master node.
- **`serde_json`** — serialisation of findings to JSON (payload for
  `POST /api/scan-result`) and for asserting the JSON shape in unit tests.
- **Edition 2024** — the default of the installed toolchain (cargo 1.98.1).
  The SQ6 proof of concept used edition 2021; there are no features in this
  project that depend on the older edition.
- **`Cargo.lock` committed** — although libraries often leave it out, it gives
  CI (`cargo audit` / `cargo deny`) a fixed set of versions to check. The
  agent and master have their own lock files that decide the final versions.

## Verification

```text
$ cargo build
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 3.38s

$ cargo test
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out

$ cargo tree --depth 1
lunarscope-modules v0.1.0
├── serde v1.0.229
└── serde_json v1.0.154
```

The crate compiles without warnings. No tests yet at this point; the code is tested from step 2 on.

## Checks (re-verified after step 10, 2026-10-17)

Step 1 has no Rust code to unit test, so its checks are about the crate's
configuration. They were run again on the final `v0.1.0` state:

| Check | Command | Result |
|-------|---------|--------|
| Crate name, version, edition | `cargo metadata --no-deps` | `lunarscope-modules`, `0.1.0`, edition `2024` ✅ |
| Crate type is `rlib` | `cargo metadata --no-deps` → library target `crate_types` | `["rlib"]` ✅ |
| Only `serde` (with `derive`) and `serde_json` as dependencies | `cargo metadata` / `cargo tree --depth 1 -e normal` | `serde ^1.0.229` features `["derive"]`, `serde_json ^1.0.154` ✅ |
| Build output is not committed | `git check-ignore -v target` | ignored by `.gitignore:1:/target` ✅ |
| Builds from the lock file | `cargo build --locked` and `cargo build --release --locked` from `cargo clean` | ✅ |
| Lint / formatting | `cargo clippy --all-targets --locked -- -D warnings`, `cargo fmt --check` | no warnings, no changes ✅ |

```text
$ cargo metadata --no-deps --format-version 1   (summarised)
name: lunarscope-modules | version: 0.1.0 | edition: 2024
target: lunarscope_modules ['rlib']
dep: serde ^1.0.229 features: ['derive']
dep: serde_json ^1.0.154 features: []
```

## Next step

Step 2 — `Severity` enum in `src/lib.rs`.
