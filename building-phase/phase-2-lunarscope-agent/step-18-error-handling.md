# Step 18 — Error handling

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

> **Update 2026-11-09:** The `interval_seconds` error example below no longer exists in agent v0.2.0. A bad `scan_time` or an old `interval_seconds` key is now a `Parse` error, see [change-0.2.0-daily-scan-time.md](change-0.2.0-daily-scan-time.md). The rest of this step is unchanged.

## Goal

No `.unwrap()` on anything that can fail at runtime; use `?` or log with
`eprintln!`. The agent must not crash on a network error. It logs the error
and waits for the next tick.

## What was done

The code was written with this rule from the start. The result:

| Kind of error | When | Behaviour |
|---------------|------|-----------|
| Bad arguments | startup | `lunarscope-agent: unknown argument '…'` + usage, **exit 1** |
| Config can't be read / parsed / is invalid | startup | One line, e.g. `lunarscope-agent: invalid config value: interval_seconds is 0, the minimum is 10`, **exit 1** |
| Unknown module name | startup | `unknown module(s) in modules.enabled: …; available: …`, **exit 1** |
| Master unreachable, timeout, TLS error | every cycle | Logged, rest of the cycle skipped, **agent keeps running** |
| 401 | every cycle | Logged with a hint, rest of the cycle skipped, keeps running |
| 400/500 for one finding | every cycle | Logged, next finding is sent, keeps running |
| Module panics | every cycle | Becomes a Low `<module>_crashed` finding (step 15), keeps running |

`main()` turns the result into an exit code:

```rust
#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    match run().await {
        Ok(true) => ExitCode::SUCCESS,      // --once: everything accepted
        Ok(false) => ExitCode::from(2),     // --once: something not accepted
        Err(err) => {
            eprintln!("lunarscope-agent: {err}");
            ExitCode::FAILURE               // startup error
        }
    }
}
```

### Remaining `unwrap`/`expect` in non-test code

```text
(every .unwrap() / .expect( in src/*.rs before the #[cfg(test)] line)
src/sender.rs: 160:     serde_json::to_vec(&payload).expect("payload serialises to JSON")
```

This one is kept on purpose. Serialising a struct of strings and integers into
memory cannot fail, so a failure there would be a programming error. All other
fallible calls use `?`, `map_err`, `unwrap_or`/`unwrap_or_else` or a `match`.

## Choices and justification

- **Startup errors exit, runtime errors don't.** A wrong config won't fix
  itself, so the agent says what is wrong and stops. systemd shows the
  service as failed (step 20). A network problem is often temporary, so the
  agent keeps its schedule and tries again on the next tick.
- **The failed cycle's findings are not stored for later.** The next cycle
  produces fresh findings anyway, and old ones would have a timestamp outside
  the master's 60 s window. Buffering would add disk writes (and a writable
  path in the systemd sandbox) for no real gain.
- **Logs go to stderr** — under systemd they end up in the journal
  (`journalctl -u lunarscope-agent`), which adds the timestamps.

## Checks

### Manual: master outage during the loop

([evidence](evidence/step-17-18-loop-with-master-outage.txt))

| Time (2026-10-29, CET) | Event | Agent |
|------|-------|-------|
| 13:16:19 | started, master **down** | "could not reach master", `not sent 3`, keeps running |
| 13:16:29 | master still down | same, keeps running |
| 13:16:31 | master started | — |
| 13:16:39 | next tick | `accepted 3` — recovered without a restart |
| 13:16:42 | master stopped | — |
| 13:16:49 | next tick | "could not reach master", keeps running |

### Manual: startup errors (all exit code 1)

```text
$ lunarscope-agent --config /nonexistent.toml
lunarscope-agent: could not read config: /nonexistent.toml: No such file or directory (os error 2)
$ … modules.enabled = [..., "package-scan"]
lunarscope-agent: unknown module(s) in modules.enabled: package-scan; available: ssh_scan, firewall_scan, package_scan
$ … master_url = "http://master.example.com"
lunarscope-agent: invalid config value: master_url 'http://master.example.com' uses plain http; use https (http is only allowed for localhost)
$ … interval_seconds = 0
lunarscope-agent: invalid config value: interval_seconds is 0, the minimum is 10
$ lunarscope-agent --bogus
lunarscope-agent: unknown argument '--bogus'
usage: lunarscope-agent [--config <path>] [--once]
```

A world-readable config (mode 644) gave the warning
`… is readable by every user and contains the API key; run 'chmod 640' on it`.

### Unit tests

`unreachable_master_aborts_without_panicking`, `unauthorized_stops_the_cycle`,
`other_error_status_skips_only_that_finding` (step 16),
`panicking_module_becomes_a_finding_and_others_still_run` (step 15) and the
config tests (step 12).

## Next step

Step 19 — release binary + size and memory.
