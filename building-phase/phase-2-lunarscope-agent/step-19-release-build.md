# Step 19 — Release binary + size and memory

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

> **Update 2026-11-09:** The measurements below were made with `interval_seconds = 10`. Since agent v0.2.0 the agent scans once a day at `scan_time`, so the long-running measurement now shows the agent waiting after its startup scan. See [change-0.2.0-daily-scan-time.md](change-0.2.0-daily-scan-time.md).

## Goal

`cargo build --release`, measure the size with `ls -lh` and the memory use
with valgrind massif or `measure.sh`.

## What was done

### Release profile (`Cargo.toml`)

Five builds were compared (same code, dev machine):

| Profile settings | Size (bytes) | |
|------------------|-------------:|---|
| default release | 7,548,808 | 7.2 MiB |
| `strip = true` | 6,050,168 | −20 % |
| + `lto = true`, `codegen-units = 1` | 5,205,192 | −31 % |
| + `opt-level = "s"` | **3,208,664** | **−57 %** |
| + `opt-level = "z"` | 3,151,976 | −58 % |

Chosen:

```toml
[profile.release]
# Smaller binary for distribution to servers (see docs, step 19).
opt-level = "s"
lto = true
codegen-units = 1
strip = true
```

- `opt-level = "z"` saves only 1.8 % more than `"s"` but optimises harder for
  size at the cost of speed. `"s"` is the usual balance.
- `strip` removes symbols. Panic messages and logs still work; only debugger
  symbol names are lost, which aren't needed on servers.
- **`panic = "abort"` is not used.** It would shrink the binary further, but
  then `catch_unwind` can no longer turn a module panic into a finding
  (step 15).

### `scripts/measure.sh`

A new script in the agent repo (based on the SQ6 PoC's `measure.sh`):

```bash
scripts/measure.sh <config.toml> [binary] [runs]
```

It reports:

| Line | How |
|------|-----|
| size | `stat -c %s` |
| `--once` time | average wall time of N `--once` runs (scan + send) |
| `--once` peak | `/usr/bin/time -f %M` — max RSS, **including child processes** |
| agent RSS | `VmRSS`/`VmHWM`/`Threads` from `/proc/<pid>/status` of the running loop after 15 s (≥ 2 cycles) |
| massif heap | `valgrind --tool=massif`, peak `mem_heap_B` of one `--once` run |

## Measurements on the target OS

Run in an **Ubuntu 24.04** container (`openssh-server`, `ufw`, `valgrind`, `time`
installed), as the unprivileged `lunarscope` user, against a local fake master
with `interval_seconds = 10`
([raw output](evidence/step-19-measurements-ubuntu.txt)):

| Metric | All three modules | Without `package_scan` |
|--------|------------------:|-----------------------:|
| Binary size | 3,208,664 B (3.1 MiB) | same |
| `--once` time (avg of 10) | 1308 ms | **9 ms** |
| Agent RSS, running loop | **4,568 kB** (peak 4,568 kB) | 4,564 kB |
| Threads | **1** | 1 |
| Peak heap (massif) | **591 kB** | 591 kB |
| Peak RSS incl. children | 103,304 kB | 6,120 kB |

`apt-get -s upgrade` measured on its own: **1.50 s, 104,000 kB max RSS**.

### Interpretation

- **The agent process itself is small and stable**: about 4.5 MB RSS on a
  single thread, the same with or without `package_scan`, and unchanged
  after several cycles (no growth).
- **Almost all time and memory of a cycle is `apt-get`.** The 103 MB and 1.3 s
  belong to the `apt-get -s upgrade` child process (it loads the package
  cache). It is freed when `apt-get` exits, once per interval (default once
  an hour). Without `package_scan` a whole cycle takes 9 ms.
- **Compared to the architecture document:**
  - "the agent uses less than 600 kB RAM": the **heap** peak is 591 kB, which
    matches, but the **resident set** is ~4.5 MB. RSS also counts the mapped
    code (the TLS stack: rustls + aws-lc crypto, HTTP client), glibc and the
    stack. The document should state "~4.5 MB RSS, < 600 kB heap".
  - The SQ6 PoC measured a 1 MB binary and 3.5 MB RSS **without** HTTPS. The
    real agent's +2.2 MB binary and +1 MB RSS are the cost of the TLS 1.3
    HTTP client. For comparison, the master is planned at ~17 MB RAM.

## Checks

- `cargo build --release --locked` from a clean state ✅ (step 21)
- The release binary's highest glibc requirement is `GLIBC_2.39`, the glibc of
  Ubuntu 24.04. A binary built on the Fedora dev machine runs on the target.
  CI should build it on Ubuntu 24.04 anyway (phase 4).
- The same release binary was used for the systemd test in step 20.
