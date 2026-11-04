# Step 26 — API key validation as a separate function

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

Move the key validation out of the handler, so the handler only works with
the already validated `agent_id`.

## What was done

### `src/auth.rs` — `authenticate()` and the `AuthenticatedAgent` extractor

```rust
/// The id of the agent that sent the request, after its API key was
/// verified. A handler that takes this as an argument only runs for
/// authenticated requests; otherwise axum answers 401 (or 500) itself.
pub struct AuthenticatedAgent(pub String);

impl FromRequestParts<AppState> for AuthenticatedAgent {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, ApiError> {
        let header = parts
            .headers
            .get(header::AUTHORIZATION)
            .and_then(|value| value.to_str().ok());
        authenticate(&state.db, header).await.map(AuthenticatedAgent)
    }
}

/// Checks an `Authorization` header value against the stored key hashes and
/// returns the agent id it belongs to.
pub async fn authenticate(pool: &SqlitePool, header: Option<&str>) -> Result<String, ApiError> {
    let token = header.and_then(bearer_token).ok_or_else(ApiError::unauthorized)?;
    queries::agent_id_by_key_hash(pool, &hash_api_key(token))
        .await
        .map_err(ApiError::internal)?
        .ok_or_else(ApiError::unauthorized)
}
```

### `src/routes/api.rs` — the handler now starts with a validated id

```rust
pub async fn scan_result(
    State(state): State<AppState>,
    AuthenticatedAgent(agent_id): AuthenticatedAgent,
    body: Result<Json<ScanResultRequest>, JsonRejection>,
) -> Result<StatusCode, ApiError> {
    // 1. Body.  2. agent_id must match.  3. Replay protection.  4. Store.
```

The header parsing and key lookup were removed from the handler.
The production code in `api.rs` no longer touches the `Authorization` header,
`hash_api_key` or the key query; only its tests do.

### `src/error.rs` — `ApiError` moved out of `api.rs`

`ApiError` (status + `{"error": …}` body, `WWW-Authenticate` on 401) is now used
by both `auth.rs` and `api.rs`, so it moved to its own module. The 500
message changed from "could not store result" to the generic
**"internal server error"**, because a database error can now also happen
during authentication. The real cause is still logged.

## Choices and justification

- **An axum extractor instead of middleware or a plain helper call.** All
  three would move the code out of the handler, but only an extractor makes
  authentication part of the handler's **type signature**. A handler that
  takes `AuthenticatedAgent` *cannot* run unauthenticated, and one that
  doesn't take it is visibly public. There's no separate list of protected
  routes that can get out of sync with the router. Future agent endpoints just
  add the argument.
- **Authentication still happens before the body is read.** axum runs
  `FromRequestParts` extractors (headers) before the `Json` body extractor,
  which must be last. The "401 before 400" behaviour from step 25 now follows
  from the signature itself. The test `authentication_is_checked_before_the_body`
  still passes without any code for it in the handler.
- **`authenticate()` as a plain async function inside the extractor.** It takes
  a pool and a header value, with no HTTP request needed, so the rules can be
  tested directly. The extractor is only the glue that reads the header.
- **The `agent_id` comparison stays in the handler.** It needs the body, and
  extractors that read headers can't see the body. It is about *what* the
  agent reports, not *who* it is.
- **A non-UTF-8 `Authorization` header** is treated like a missing one (401),
  not a 400 or a panic.

## Checks — unit tests

### New in `src/auth.rs`

| Test | Checks |
|------|--------|
| `authenticate_returns_the_agent_of_a_valid_key` | `Bearer valid-key` → `agent-1` |
| `authenticate_rejects_missing_malformed_and_unknown_keys` | No header, empty, key without scheme, `Basic`, `Bearer `, unknown key, **the stored hash used as the key** → 401 each |
| `authenticate_reports_database_errors_as_500` | Closed pool → 500 "internal server error" |
| `extractor_gives_handler_the_agent_id` | A test route `whoami(AuthenticatedAgent(id))` returns `agent-1` |
| `extractor_answers_401_without_running_the_handler` | Wrong key → 401, body `{"error":"invalid or missing API key"}`, `WWW-Authenticate: Bearer`, handler not run |
| `extractor_rejects_non_utf8_header` | `Authorization: Bearer \xff\xfe` → 401 |

### Refactoring safety

All 17 handler tests from step 25 were left **unchanged** (only their
imports moved) and still pass. The API's behaviour (status codes, messages,
order of checks) is the same as before the refactoring.

### Mutation checks

| Bug introduced | Failing tests |
|----------------|---------------|
| unknown key accepted (empty agent id instead of 401) | `authenticate_rejects_missing_malformed_and_unknown_keys`, `extractor_answers_401_without_running_the_handler`, `authentication_is_checked_before_the_body` |
| extractor reads `Proxy-Authorization` instead of `Authorization` | `extractor_gives_handler_the_agent_id` + 8 API tests |
| database error answered with 401 | `authenticate_reports_database_errors_as_500`, `database_failure_is_500` |

### Results

```text
$ cargo test                                → 54 passed, 0 failed
$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

## Next step

Step 27 — `POST /api/register-agent`: create an agent and return its newly
generated API key.
