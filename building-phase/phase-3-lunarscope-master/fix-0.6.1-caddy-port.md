# Fix 0.6.1: Caddy proxies to the port the master listens on

## Problem

Found while comparing the code with the architecture design
([architecture-as-built.md](../architecture-as-built.md), section 8):

- `lunarscope-master.service` starts the master with `--listen 127.0.0.1:3000`
  (the production port, also the default in `src/main.rs` and in the docs of
  steps 32–33 and the code overview).
- `install/Caddyfile` (added in 0.4.0) proxied to `127.0.0.1:3030`, the port
  of the **development** service on the laptop (`scripts/install-dev-service.sh`,
  because 3000 is taken there).

A fresh install with both files as shipped would answer every request with
**502 Bad Gateway**: Caddy finds nothing on 3030.

## Fix

- `install/Caddyfile`: `reverse_proxy 127.0.0.1:3000`, and the comment at the
  top says it must match the `--listen` of the service, and that on the dev
  laptop the master runs on 3030.
- The production port stays 3000; nothing changes for the dev service on 3030.
- New test `caddy_proxies_to_the_address_the_service_listens_on`
  (`src/main.rs`): reads both files at compile time (`include_str!`), takes the
  value after `--listen` in the service and every `reverse_proxy` address in
  the Caddyfile, and requires that they are the same and on `127.0.0.1`.

## Checks

| Check | Result |
|-------|--------|
| `cargo test` | 361 passed (1 new) |
| `cargo fmt --check`, `cargo clippy --all-targets -D warnings` | clean |
| Mutation: Caddyfile back to `3030` | test fails: `left: ["127.0.0.1:3030"]`, `right: ["127.0.0.1:3000"]`; restored afterwards |
| `caddy validate` | not run: Caddy is not installed on the dev laptop |

No change to the running `lunarscope` service on 3030.
