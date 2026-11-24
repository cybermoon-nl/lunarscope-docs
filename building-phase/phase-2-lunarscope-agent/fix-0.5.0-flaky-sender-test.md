# Fix (agent 0.5.0): flaky test `sends_one_authenticated_post_per_finding`

## Problem

In the CI on the self-hosted runner, one test failed once:

```
---- sender::tests::sends_one_authenticated_post_per_finding stdout ----
assertion `left == right` failed
  left: 1
 right: 2
```

Locally it always passed (77/77).

## Cause

The fake master in the tests (`fake_master` and `fake_config_master` in
`src/sender.rs`) runs on its own thread. For each request it **first wrote
the HTTP answer and only then passed the request to the test** through a
channel. When the agent receives the answer to its last request, the test
reads the channel at once (`try_iter`). On a busy runner the thread had not
yet passed the second request, so the test saw 1 request instead of 2. The
agent itself did nothing wrong: both findings were accepted (`accepted: 2`).

## Fix

Both fake masters now pass the request to the test **before** they answer.
The agent only continues after the answer, so by the time the test looks,
every request is there. Test code only; the agent itself is unchanged.

## Checks

| Check | Result |
|-------|--------|
| `cargo test --locked`, 10 times in a row | 77/77 each time |
| `cargo fmt --check`, `cargo clippy --locked --all-targets --all-features -D warnings` | clean |
