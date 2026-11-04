# Step 11 — Repo + binary crate

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

## Goal

Turn the `lunarscope-agent` repo into a binary crate that depends on
`lunarscope-modules` through a git URL, plus tokio, reqwest (with TLS),
serde_json, toml and serde.

## What was done

As in step 1, the repo already existed (README + `.github/`), so the crate was
initialised in place and the dependencies were added with `cargo add`:

```bash
cd repos/lunarscope-agent
cargo init --bin --name lunarscope-agent
cargo add lunarscope-modules --git https://github.com/cybermoon-nl/lunarscope-modules --tag v0.1.0
cargo add tokio --no-default-features --features rt,macros,time
cargo add serde --features derive
cargo add serde_json toml
cargo add reqwest --no-default-features --features rustls
```

### `Cargo.toml` (dependencies)

```toml
[dependencies]
lunarscope-modules = { git = "https://github.com/cybermoon-nl/lunarscope-modules", tag = "v0.1.0", version = "0.1.0" }
reqwest = { version = "0.13.5", default-features = false, features = ["rustls"] }
serde = { version = "1.0.229", features = ["derive"] }
serde_json = "1.0.154"
tokio = { version = "1.54.1", default-features = false, features = ["rt", "macros", "time"] }
toml = "1.1.8"
```

The `[profile.release]` section was added later, in step 19.

## Choices and justification

- **Git dependency pinned to `tag = "v0.1.0"`** — the agent builds against
  exactly the released library. `Cargo.lock` records the commit:
  `git+https://github.com/cybermoon-nl/lunarscope-modules?tag=v0.1.0#c8015c3…`,
  which is the commit the `v0.1.0` tag points to on GitHub. New commits to the
  library never change the agent without a deliberate version bump. (The
  architecture document's URL has the typo `lunarscape-modules`; the real repo
  name is used.)
- **tokio with only `rt`, `macros`, `time`** — the agent needs a runtime for
  reqwest, `#[tokio::main]` and `tokio::time::interval`. The multi-threaded
  scheduler (`rt-multi-thread`), networking, file system and signal features
  are not needed. Fewer features means a smaller binary and less memory
  (step 19).
- **reqwest without default features, with `rustls`** — `rustls` is a TLS stack
  written in Rust, so there's no dependency on the system's OpenSSL version.
  In reqwest 0.13 the `rustls` feature uses the `aws-lc-rs` crypto provider
  and `rustls-platform-verifier`, which trusts the OS certificate store
  (`ca-certificates` on Ubuntu). That fits the Let's Encrypt certificate
  planned for the master. reqwest's `json` feature isn't needed, because the
  body is serialised with `serde_json` directly (step 16).
- **`toml` + `serde`** — config parsing (step 12); `serde_json` — request body
  (step 16).

## Checks

| Check | Result |
|-------|--------|
| `cargo build` with all dependencies (first build, 15 s) | ✅ |
| `Cargo.lock` source of `lunarscope-modules` | `?tag=v0.1.0#c8015c3057b6…` = `refs/tags/v0.1.0^{}` on GitHub ✅ |
| `git ls-remote --tags origin` in `lunarscope-modules` | `v0.1.0` present ✅ |

### Note on the local `lunarscope-modules` checkout

On 2026-10-29 the local `lunarscope-modules` working tree had an uncommitted
change from 2026-10-20: `edition = "2026"` in `Cargo.toml`. cargo 1.98 only
supports editions up to 2024, so that local checkout no longer builds. The
agent is **not** affected, because it fetches the `v0.1.0` tag from GitHub.
The change was left as it is; revert it with
`git -C repos/lunarscope-modules checkout Cargo.toml` if it was not intentional.

*Update 2026-11-04: the change was reverted; the local checkout builds again.*

## Next step

Step 12 — `Config` struct + loading.
