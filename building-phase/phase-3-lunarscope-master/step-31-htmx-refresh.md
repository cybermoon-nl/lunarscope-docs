# Step 31 — HTMX refresh

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

Add `hx-get="/" hx-trigger="every 30s"` to the findings block in
`dashboard.html`, so it refreshes on its own.

## What was done

### Templates

```html
{% block findings %}
<section id="findings" hx-get="/" hx-trigger="every 30s" hx-swap="outerHTML">
    <p class="muted">Latest scan results per server. Updated {{ generated_at }}.</p>
    … table …
</section>
{% endblock findings %}
```

The detail page got the same, polling its own URL:
`hx-get="/server/{{ agent.id }}"`. The "Updated …" time and the detail page's
last-seen line moved **inside** the block, so they refresh too.

### Server: only the block for an HTMX request

HTMX adds `HX-Request: true` to its requests. Both page handlers now call
`templates::render_page()`:

```rust
let rendered = if is_htmx(headers) {
    tera.render_block(name, FINDINGS_BLOCK, &context)   // just <section id="findings">…</section>
} else {
    tera.render(name, &context)                         // whole page
};
// + Vary: HX-Request, Cache-Control: no-store
```

### HTMX itself: `static/htmx.min.js`

**htmx 2.0.11** was downloaded (with permission) from the npm registry and
checked against npm's published **SHA-512 checksum** before use
([download log](evidence/step-31-htmx-download.txt)). The file is **embedded**
in the binary (`include_str!`) and served by a small handler:

| | |
|---|---|
| Route | `GET /static/htmx.min.js` |
| Content-Type | `text/javascript; charset=utf-8` |
| Cache-Control | `public, max-age=86400` |
| Licence | 0BSD, kept as `static/htmx.LICENSE` |

### Files

| File | Change |
|------|--------|
| `templates/dashboard.html`, `templates/server.html` | `{% block findings %}` + `hx-get`/`hx-trigger`/`hx-swap` |
| `src/templates.rs` | `is_htmx()`, `render_page()`, `FINDINGS_BLOCK`; 2 new tests |
| `src/routes/dashboard.rs`, `src/routes/server.rs` | use `render_page()` with the request headers; 5 + 3 new tests |
| `src/routes/static_files.rs` | New — embedded htmx, 3 tests |
| `static/htmx.min.js`, `static/htmx.LICENSE` | New |
| `src/main.rs` | Route `GET /static/htmx.min.js` |
| `Cargo.toml` | **`tower-http` removed** |

## Choices and justification

- **`hx-swap="outerHTML"`** — the guide only gives `hx-get` and `hx-trigger`.
  HTMX's default swap is `innerHTML`: it puts the answer *inside* the section,
  so the page would get a section within a section, a bit deeper every 30 s.
  With `outerHTML` the answer replaces the section. Because the answer is a
  section with the same `hx-*` attributes, HTMX picks them up again and
  polling continues (confirmed live: 2 refreshes, never nested).
- **Only the block is sent** (`render_block`) instead of the whole page. The
  alternative, `hx-select="#findings"` on the client, would download the full
  page every 30 s and throw most of it away. Measured: **1,121 bytes per
  refresh instead of 3,193**. The database query and data are the same, so the
  two versions can't drift apart.
- **`Vary: HX-Request` + `Cache-Control: no-store`** — the same URL returns two
  different bodies (page or fragment). Without `Vary`, a browser or proxy cache
  could show a bare fragment when the admin opens `/`, or a full page inside
  the section. `no-store`: a security dashboard should never show stale data
  from a cache.
- **Errors keep the old table** — HTMX doesn't swap error responses (4xx/5xx)
  by default. If the database fails during a refresh, the last good table
  stays visible and the next tick tries again (the test
  `htmx_refresh_with_database_failure_is_500` checks that the server answers
  500, not a broken fragment).
- **The detail page refreshes too** — the guide only mentions the dashboard.
  An admin who keeps a server's page open while fixing something sees the
  result as soon as the agent reports. It is the same mechanism with no extra
  code.
- **HTMX embedded instead of served from a directory with `tower-http`.**
  Step 22 added `tower-http` (`ServeDir`) for static files. In the end there is
  exactly **one** static file, and embedding it is consistent with the
  migrations (step 23) and templates (step 28): the master stays a single
  binary with no static directory to deploy or allow in the systemd sandbox.
  `tower-http` and its dependency tree were removed, which also means fewer
  licences for `cargo deny` (step 37).
- **Verified download** — the file runs in the administrator's browser, so it
  is part of the security of the dashboard. It came from the official npm
  package, its SHA-512 was compared with npm's published value, and its
  SHA-256 is pinned in a test. Any change to the file, accidental or not,
  fails `cargo test`.
- **`max-age=86400`** for htmx — the file only changes with a new master
  release. Browsers fetch it at most once a day instead of on every page load.

## Checks

### Unit tests

| Test | Checks |
|------|--------|
| `full_page_polls_the_findings_block` | Full page has `<section id="findings" hx-get="/" hx-trigger="every 30s" hx-swap="outerHTML">` |
| `htmx_refresh_gets_only_the_findings_block` | `HX-Request: true` → starts with that section (attributes kept, so polling continues), ends with `</section>`, no doctype/nav/script |
| `htmx_refresh_shows_new_data` | A Critical result added between two refreshes appears in the second |
| `pages_are_not_cached_and_vary_on_hx_request` | `Cache-Control: no-store`, `Vary: HX-Request` on both forms |
| `htmx_refresh_with_database_failure_is_500` | 500, so HTMX keeps the old table |
| `detail_page_polls_its_own_url` | `hx-get="/server/a1"` |
| `htmx_refresh_of_detail_page_gets_only_the_block` | Fragment, no `<h1>`, `Vary` header |
| `agent_id_in_hx_get_is_escaped` | An id with `" onclick="` can't break out of the `hx-get` attribute |
| `is_htmx_only_for_hx_request_true` | No header / `false` → full page; `true` → fragment |
| `findings_block_renders_alone_and_escaped` | `render_block` output is just the section, still HTML-escaped |
| `embedded_file_is_htmx_2_0_11` | SHA-256 of the embedded file equals the verified one; version 2.0.11 |
| `htmx_is_served_as_javascript` | 200, JavaScript content type, cache header, full length |
| `other_static_paths_are_404` | `/static/`, other names, `../Cargo.toml`, the licence file → 404 |

The step 28 test `dashboard_lists_agents_with_counts_and_link` was updated for
the new attributes on the section.

Total master tests: **129**, all passing.

### Mutation checks

| Bug introduced | Failing tests |
|----------------|---------------|
| `hx-swap="outerHTML"` removed | `full_page_polls_the_findings_block`, `htmx_refresh_gets_only_the_findings_block`, `dashboard_lists_agents_with_counts_and_link` |
| polling every 300 s | same three |
| HTMX request gets the whole page | `htmx_refresh_gets_only_the_findings_block`, `htmx_refresh_of_detail_page_gets_only_the_block` |
| any `HX-Request` value counts as HTMX | `is_htmx_only_for_hx_request_true` |
| no `Vary` header | `pages_are_not_cached_and_vary_on_hx_request`, `htmx_refresh_of_detail_page_gets_only_the_block` |
| detail page polls `/` | `detail_page_polls_its_own_url`, `htmx_refresh_of_detail_page_gets_only_the_block` |

### Live check in a browser

The master doesn't listen on a port until step 32, so a temporary test
(removed afterwards) served the router on `127.0.0.1:38131` with a small
database, and the dashboard was opened in a browser
([full log](evidence/step-31-live-htmx-check.txt)):

| Check | Result |
|-------|--------|
| htmx loaded from the master | `htmx.version` = `2.0.11` |
| New Critical result written to the database | Shown **without reload** within one interval; page marker still present (same document) |
| Polling continues after a swap | Refreshes at 30 s and 60 s; 2 swaps; still exactly one `#findings` section, none nested |
| Size per refresh | 1,121 bytes (fragment) vs 3,193 bytes (page) |
| Detail page | Refreshes the same way, one `<h1>`, rows sorted |
| Headers | `vary: HX-Request`, `cache-control: no-store` |

```text
$ cargo test                                → 129 passed, 0 failed
$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

## Next step

Step 32 — combine all routes in `main.rs` and bind to `0.0.0.0:3000`.
