# Fix 0.1.1 — clear startup error without `ca-certificates`

**Repo:** `lunarscope-agent`
**Date:** 2026-11-04
**Status:** Done — code and checks ready; commit + tag `v0.1.1` by hand

## Why

The [re-test of 2026-11-04](../retest-2026-11-04.md) found that on a system
without the `ca-certificates` package the agent stops at startup with:

```text
lunarscope-agent: invalid config value: could not create HTTP client: builder error
```

Stopping is correct (without trusted CAs the master's certificate can't be
verified), but the message is misleading: the config is fine, and the real
cause is hidden.

**Cause.** `Reporter::new` in `src/sender.rs` builds the reqwest 0.13 client
(`rustls` feature, which uses `rustls-platform-verifier`). That verifier loads
the system's CA certificates when the client is built and fails if there are
none. The error was wrapped as `ConfigError::Invalid`, and only its top-level
text ("builder error") was shown.

## What was done

All in `src/sender.rs`:

1. **Own error kind.** New `ReporterError` enum, returned by
   `Reporter::new`:
   - `ReporterError::Config(ConfigError)` — a bad `master_url`, as before
     (message unchanged; `From<ConfigError>` lets `?` convert it).
   - `ReporterError::HttpClient(String)` — building the HTTP client failed.

   "Could not create HTTP client" is no longer a `ConfigError::Invalid`.
2. **Full error chain.** The build error is passed through the existing
   `error_chain()` (step 16), so the cause behind "builder error" is shown.
3. **Hint.** The message ends with "(is the ca-certificates package
   installed?)".

```rust
ReporterError::HttpClient(msg) => write!(
    f,
    "could not create HTTP client: {msg} (is the ca-certificates package installed?)"
),
```

`main.rs` didn't need a change: it already turns the error into text with
`to_string()`.

4. **Version** in `Cargo.toml` bumped to `0.1.1` (`Cargo.lock` follows).
5. **Docs:** `ca-certificates` added as a requirement to the install section
   of [step 20](step-20-systemd-unit.md).

New message on a system without CA certificates:

```text
lunarscope-agent: could not create HTTP client: builder error: unexpected error: No CA certificates were loaded from the system (is the ca-certificates package installed?)
```

## Tests

Two new unit tests in `sender::tests`:

| Test | Checks |
|------|--------|
| `http_client_error_names_ca_certificates` | Exact text of `ReporterError::HttpClient`, including the error chain and the hint |
| `config_error_keeps_its_own_message` | A `ConfigError` wrapped in `ReporterError` still prints "invalid config value: …" |

## Checks

On the development machine (Fedora, rustc 1.98.1):

| Check | Command | Result |
|-------|---------|--------|
| Tests | `cargo test --locked` | ✅ **35 passed** (33 + 2 new), 0 failed |
| Lint | `cargo clippy --all-targets --all-features --locked -- -D warnings` | ✅ no warnings |
| Formatting | `cargo fmt --check` | ✅ no changes |
| Release build | `cargo build --release` | ✅ 3,209,176 bytes (v0.1.0: 3,208,664) |

### On bare Ubuntu 24.04

Release binary run in the official image
(`docker.io/library/ubuntu:24.04`, digest
`sha256:a2d43bffc46670d7108bb3c0468c67c5557c4c92e83e1e34cbff1322ad1b94dc`)
with podman, `--once`, and a valid config with
`master_url = "https://lunarscope.example.com"`:

| Run | `ca-certificates` | Output | Exit |
|-----|-------------------|--------|-----:|
| Bare image | not installed (`/etc/ssl/certs` missing) | `lunarscope-agent: could not create HTTP client: builder error: unexpected error: No CA certificates were loaded from the system (is the ca-certificates package installed?)` | 1 |
| Control | installed with `apt-get` | `lunarscope-agent 0.1.1 started: …`, then `could not reach master … dns error` (the example host doesn't exist) | 2 |

The control run shows that with the package installed the agent gets past
client creation, and that the binary reports version 0.1.1.

## Mutation checks

| Deliberate bug | Caught by | Result |
|----------------|-----------|--------|
| Hint removed from the `HttpClient` message | `http_client_error_names_ca_certificates` | ✅ test fails |
| Error mapped back to `ConfigError::Invalid` / chain not used | Bare Ubuntu run above (the message would again say "invalid config value: … builder error") | ✅ checked by hand only |

The second one is not covered by a unit test: the client build can't be made
to fail on a machine that has CA certificates without changing the code for
testing. The container run is the check for it.

## Not changed

- The 6 `sender::tests` that fail on a bare image (re-test) still fail there.
  They need a working HTTP client, so that is expected; with
  `ca-certificates` installed they pass.

## Files to commit in `lunarscope-agent`

```text
Cargo.toml
Cargo.lock
src/sender.rs
```

## Commit and tag (done by hand)

From `repos/lunarscope-agent`:

```bash
git add Cargo.toml Cargo.lock src/sender.rs
git status
git commit -m "Clear startup error when no CA certificates are installed (v0.1.1)"
git pull --rebase origin main
git tag -a v0.1.1 -m "lunarscope-agent v0.1.1"
git push origin main
git push origin v0.1.1
```

Docs, from `repos/lunarscope-docs`:

```bash
git add building-phase/README.md building-phase/phase-2-lunarscope-agent/fix-0.1.1-ca-certificates.md building-phase/phase-2-lunarscope-agent/step-20-systemd-unit.md
git commit -m "Document lunarscope-agent v0.1.1 (ca-certificates error)"
git push origin main
```
