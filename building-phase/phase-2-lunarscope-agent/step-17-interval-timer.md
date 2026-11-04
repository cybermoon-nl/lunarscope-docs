# Step 17 — Interval timer

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

## Goal

Wrap the scan cycle in `tokio::time::interval(Duration::from_secs(config.interval_seconds))`
with `loop { interval.tick().await; scan(); }`.

## What was done

`src/main.rs`:

```rust
#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode { /* calls run(), see step 18 */ }

async fn run() -> Result<bool, String> {
    let args = parse_args(std::env::args().skip(1))?;
    let config = Config::load(&args.config_path).map_err(|err| err.to_string())?;
    let modules = get_enabled_modules(&config)?;
    let reporter = Reporter::new(&config, hostname()).map_err(|err| err.to_string())?;
    // startup log line

    if args.once {
        return Ok(cycle(&modules, &reporter).await);
    }

    // The first tick completes immediately, so the agent scans at startup.
    let mut interval = tokio::time::interval(Duration::from_secs(config.interval_seconds));
    interval.set_missed_tick_behavior(MissedTickBehavior::Delay);
    loop {
        interval.tick().await;
        cycle(&modules, &reporter).await;
    }
}
```

`cycle()` = `scan()` (step 15) + `send_all()` (step 16) + one summary log line.

### Command-line arguments

| Argument | Default | Meaning |
|----------|---------|---------|
| `--config <path>` | `/etc/lunarscope/config.toml` | Config file (the `ExecStart` in the architecture document passes it this way) |
| `--once` | off | Run one cycle and exit: exit 0 if every finding was accepted, exit 2 otherwise. For checking an installation and for the measurements in step 19 |

Parsed by a small `parse_args()`. No `clap` dependency is needed for two
flags.

## Choices and justification

- **`current_thread` runtime** — the agent does one thing at a time (scan,
  then send), so one thread is enough. The multi-threaded runtime would start
  a worker thread per CPU core and use more memory. Step 19 measured
  **1 thread** for the running agent.
- **First tick immediate** — `interval()` completes its first tick at once, so
  a freshly installed or restarted agent reports right away instead of after
  an hour.
- **`MissedTickBehavior::Delay`** — the default (`Burst`) would run the missed
  cycles back to back if a cycle ever took longer than the interval, e.g. a
  slow `apt-get`. `Delay` waits a full interval after a late tick instead.
- **Timer measures from tick to tick, not from the end of a cycle** — with a
  1.2 s cycle and a 3600 s interval, scans start at 0 s, 3600 s, 7200 s, … and
  don't drift.

## Checks

- `default_args`, `config_and_once_flags`, `bad_args_are_errors` (unit tests)
  cover argument parsing.
- **Manual loop run** with `interval_seconds = 10` (2026-10-29, local time CET): cycles at 13:16:19,
  :29, :39, :49 — exactly 10 s apart, the first one immediately at startup
  ([evidence](evidence/step-17-18-loop-with-master-outage.txt)).
- Under systemd (step 20), cycles were logged every 10 s for the whole test.

## Next step

Step 18 — error handling.
