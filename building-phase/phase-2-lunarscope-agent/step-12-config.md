# Step 12 — Config struct + loading

**Repo:** `lunarscope-agent`
**Date:** 2026-10-29
**Status:** Done

## Goal

`src/config.rs` with `struct Config { agent_id, api_key, master_url,
interval_seconds, modules: ModulesConfig }` and `struct ModulesConfig
{ enabled: Vec<String> }`, loaded with `toml::from_str`.

## What was done

```rust
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub agent_id: String,
    pub api_key: String,
    pub master_url: String,
    pub interval_seconds: u64,
    pub modules: ModulesConfig,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModulesConfig {
    pub enabled: Vec<String>,
}
```

| Function | Responsibility |
|----------|----------------|
| `Config::load(path)` | Reads the file, warns if it is world-readable, calls `parse` |
| `Config::parse(content)` | `toml::from_str` + `validate()` |
| `validate()` | Checks the values (table below) |
| `master_base_url()` | Parses `master_url` and enforces https |

Errors are a small `ConfigError` enum (`Read`, `Parse`, `Invalid`) with a
`Display` implementation, so the agent prints one clear line and exits
(step 18). No extra crate (such as `thiserror`) is needed for this.

### Validation

| Rule | Why |
|------|-----|
| Unknown keys are an error (`deny_unknown_fields`) | A typo like `interval_second` would otherwise be ignored silently, and a missing required key gives a confusing error |
| `agent_id`, `api_key` not empty | The master can't authenticate without them |
| `interval_seconds` ≥ 10 (`MIN_INTERVAL_SECONDS`) | `tokio::time::interval(0)` **panics**; very small values would flood the master. Negative values are already a parse error (`u64`) |
| `modules.enabled` not empty | An agent that scans nothing is a configuration mistake |
| `master_url` must be `https://…`; `http://` only for `localhost`, `127.0.0.1`, `[::1]` | The API key is sent with every request; over plain http it can be sniffed. Localhost http is allowed for development and the end-to-end test (step 33) |
| Warning if the file is world-readable (`mode & 0o004`) | The file contains the API key; it should be `640 root:lunarscope` (step 20) |

Unknown **module names** are checked in the module registry (step 14),
because only the registry knows which modules exist.

## Choices and justification

- **Flat structure from the guide, not the `[master]`/`[scan]` sections from
  the architecture document (3.1.4).** The building-phase guide defines the
  struct with top-level `agent_id`, `api_key`, `master_url`,
  `interval_seconds` and a `[modules]` table. That was followed, because it
  is the newer plan and keeps the struct one level deep. It also adds
  `agent_id`, which the API payload needs and the architecture's config
  example lacked. The architecture document's config examples (3.1.4, 6.3)
  should be updated to match.
- **Validation at startup** — all config mistakes are reported once, when the
  service starts. They don't show up later as a failing request every hour.

## Checks — unit tests (`src/config.rs`)

| Test | Checks |
|------|--------|
| `parses_valid_config` | All five fields are read correctly |
| `example_config_in_repo_is_valid` | The `config.toml` shipped in the repo (step 13) parses and validates (`include_str!`) |
| `missing_field_is_parse_error` | Missing `interval_seconds` → `Parse` error naming the field |
| `unknown_field_is_parse_error` | `interval_second` typo → `Parse` error naming it |
| `wrong_type_is_parse_error` | `interval_seconds = "hourly"` → `Parse` error |
| `negative_interval_is_parse_error` | `-5` → `Parse` error |
| `too_small_interval_is_rejected` | 0, 1, 9 rejected; exactly 10 accepted |
| `empty_values_are_rejected` | Empty `api_key` (whitespace), `agent_id`, `modules.enabled` |
| `plain_http_only_allowed_for_localhost` | http to localhost / 127.0.0.1 / [::1] OK; to a domain or 10.0.0.5 rejected |
| `bad_master_url_is_rejected` | No scheme, `ftp://` |
| `missing_file_is_read_error` | `Read` error containing the path |
| `load_reads_file_from_disk` | `load()` reads a real file |

Mutation checks: removing `deny_unknown_fields` → `unknown_field_is_parse_error`
fails; allowing http everywhere → `plain_http_only_allowed_for_localhost`
fails; removing the minimum interval → `too_small_interval_is_rejected` fails.

The binary's behaviour with bad configs was also checked by hand (exit
code 1 and one error line each). See step 18.

## Next step

Step 13 — example `config.toml`.
