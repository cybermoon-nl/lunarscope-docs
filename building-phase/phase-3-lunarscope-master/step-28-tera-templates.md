# Step 28 — Tera templates

**Repo:** `lunarscope-master`
**Date:** 2026-11-04
**Status:** Done

## Goal

A `templates/` directory with `base.html` (navbar + HTMX script tag) and
`dashboard.html` that extends `base.html`.

## What was done

### Files

| File | Change |
|------|--------|
| `templates/base.html` | New — HTML skeleton, inline CSS, HTMX script tag, navbar, `content` block |
| `templates/dashboard.html` | New — extends `base.html`; table of servers with severity counts |
| `src/templates.rs` | New — embeds and parses the templates, `render()` helper, view model (`DashboardView`, `AgentSummary`, `SeverityCounts`), 10 tests |
| `src/main.rs` | `AppState` gets `templates: Arc<Tera>` |

### `base.html`

- `<!doctype html>`, `lang="en"`, `charset`, `viewport` (mobile), title block
  (`<page> · Lunarscope`).
- **Navbar**: "Lunarscope" (link to `/`) and "Dashboard".
- **HTMX**: `<script src="/static/htmx.min.js" defer></script>`.
- A small inline `<style>`: one colour per severity (`.sev-Critical` …
  `.sev-Pass`), table layout, and a `.stale` class for agents that stopped
  reporting.
- `{% block content %}{% endblock %}` for the page.

### `dashboard.html`

```html
{% extends "base.html" %}

{% block title %}Dashboard{% endblock %}

{% block content %}
<h1>Servers</h1>
<p class="muted">Latest scan results per server. Generated {{ generated_at }}.</p>

<section id="findings">
    {% if agents | length == 0 %}
    <p class="empty">No agents have reported yet.</p>
    {% else %}
    <div class="table-wrap">
    <table>
        <thead>
            <tr>
                <th>Server</th>
                <th>Last seen</th>
                <th>Status</th>
                <th class="count">Critical</th>
                <th class="count">High</th>
                <th class="count">Medium</th>
                <th class="count">Low</th>
                <th class="count">Pass</th>
            </tr>
        </thead>
        <tbody>
            {% for agent in agents %}
            <tr>
                <td><a href="/server/{{ agent.id }}">{{ agent.hostname }}</a></td>
                <td{% if agent.stale %} class="stale"{% endif %}>{{ agent.last_seen }}</td>
                <td>{% if agent.worst %}<span class="badge sev-{{ agent.worst }}">{{ agent.worst }}</span>{% else %}<span class="muted">no results</span>{% endif %}</td>
                <td class="count">{{ agent.counts.critical }}</td>
                <td class="count">{{ agent.counts.high }}</td>
                <td class="count">{{ agent.counts.medium }}</td>
                <td class="count">{{ agent.counts.low }}</td>
                <td class="count">{{ agent.counts.pass }}</td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
    </div>
    {% endif %}
</section>
{% endblock %}
```

The table of servers sits in `<section id="findings">`. That is the block
step 31 refreshes with HTMX every 30 s.

### View model (`src/templates.rs`)

```rust
pub struct DashboardView {
    pub generated_at: String,
    pub agents: Vec<AgentSummary>,
}

pub struct AgentSummary {
    pub id: String,
    pub hostname: String,
    pub last_seen: String,           // already formatted, e.g. "2026-11-04 10:12 UTC" or "never"
    pub stale: bool,                 // stopped reporting
    pub worst: Option<Severity>,     // None: never reported
    pub counts: SeverityCounts,      // critical, high, medium, low, pass
}
```

Step 29 fills these from the database; this step only defines them and
tests the template with hand-made values. Until step 29 uses them they carry
a temporary `#[cfg_attr(not(test), allow(dead_code))]`.

## Choices and justification

### Templates embedded in the binary

```rust
const TEMPLATES: &[(&str, &str)] = &[
    ("base.html", include_str!("../templates/base.html")),
    ("dashboard.html", include_str!("../templates/dashboard.html")),
];
```

The guide's `templates/` directory exists in the repo, but the files are
compiled in with `include_str!` and loaded with `add_raw_templates`, rather
than read from disk at startup (`load_from_glob`):

- The master stays **one file** to deploy, like the migrations (step 23).
- There's no templates path to configure, and nothing extra to allow in the
  systemd sandbox (`ProtectSystem=strict`).
- A broken template can't be deployed by accident. `all_templates_parse`
  fails the build in CI, and `AppState::new()` parses them at startup.
- Tera's `glob_fs` feature isn't needed (step 22). `include_str!` also tells
  cargo to rebuild when a template changes, so no `build.rs` line is needed
  (unlike the migrations).

The trade-off is that template changes need a rebuild. For a prototype with
releases through CI, that is fine.

### Tera 2 specifics

- **Autoescaping** is on by default for templates whose name ends in `.html`.
  Every value is HTML-escaped unless marked `| safe`, and no template uses
  `| safe`.
- Tera 2 has **no `date` filter**, unlike Tera 1. Timestamps are therefore
  formatted in Rust (step 29) and handed to the template as text
  (`last_seen`, `generated_at`).
- `render()` turns a rendering error into a logged error plus a plain
  **500**, so the browser never gets half a page.

### Escaping matters here: agent data is untrusted

`hostname` (and, on the detail page, `description`/`remediation`) are
**sent by the agents**. A compromised server could report a hostname like
`<script>…</script>` to run JavaScript in the administrator's browser
(stored XSS). The test `agent_data_is_html_escaped` renders exactly that, plus
an `id` that tries to break out of the `href` attribute. It checks that both
come out as harmless text (`&lt;script&gt;alert(1)&lt;/script&gt;`). The
browser check below confirms the page shows the text and doesn't run it.

### HTMX served by the master, not a CDN

The script tag points at `/static/htmx.min.js` on the master itself:

- the dashboard keeps working on a network without internet access;
- no third party (CDN) learns who opens the dashboard and when;
- a compromised CDN can't inject code into the admin's browser.

The test `base_loads_htmx_from_the_master_itself` checks that the rendered
page has no `http://`/`https://` URLs at all. **The `htmx.min.js` file itself
is not in the repo yet.** It is added together with the static-file route
(steps 31–32). Until then the browser just gets a 404 for the script, and the
page works without it.

### Inline CSS

About 25 lines of CSS sit in `base.html` instead of a separate stylesheet:
one request less, nothing more to serve or cache-bust. The colours encode
severity, but each badge also shows the **word** (High, Pass, …), so the
page doesn't rely on colour alone.

### Mobile

The table has 8 columns. On a phone it scrolls **inside** its box
(`.table-wrap { overflow-x: auto }`) instead of making the whole page wider.
This was added after the first browser check showed the table overflowing
the page at 278 px width.

## Checks

### Unit tests (`src/templates.rs`)

| Test | Checks |
|------|--------|
| `all_templates_parse` | Every embedded template is loaded |
| `dashboard_extends_base` | Output starts with `<!doctype html>`, has the title "Dashboard · Lunarscope", charset, viewport, navbar, ends with `</html>` |
| `base_loads_htmx_from_the_master_itself` | `<script src="/static/htmx.min.js" defer>`; no external URL in the page |
| `dashboard_lists_agents_with_counts_and_link` | Link `/server/<id>` with hostname, last seen, badge `sev-High`, all 5 counts, `<section id="findings">`, scroll wrapper |
| `agent_without_results_shows_no_badge` | `worst: None` → "no results", no badge |
| `stale_agent_is_marked` | `<td class="stale">` |
| `empty_dashboard_shows_message` | "No agents have reported yet.", no table |
| `agent_data_is_html_escaped` | `<script>` hostname and a quote-injecting id are escaped |
| `no_template_syntax_left_in_output` | No `{{`, `}}`, `{%`, `%}`, `{#` in the HTML |
| `rendering_an_unknown_template_is_500` | `render()` error → 500 |

Total master tests: **82**, all passing.

### Mutation checks

| Change | Failing tests |
|--------|---------------|
| autoescaping turned off (`autoescape_on([])`) | `agent_data_is_html_escaped` |
| `{{ agent.hostname \| safe }}` | `agent_data_is_html_escaped` |
| HTMX loaded from `https://unpkg.com/…` | `base_loads_htmx_from_the_master_itself` |
| `{% extends %}` removed from the dashboard | `dashboard_extends_base`, `base_loads_htmx_from_the_master_itself` |
| `id="findings"` removed | `dashboard_lists_agents_with_counts_and_link` |

### Browser check

A sample dashboard (4 servers: one with High findings, one all Pass, one
stale with a `<script>alert(1)</script>` hostname, one that never reported)
was rendered to HTML and opened in a browser
([rendered file](evidence/step-28-dashboard-sample-render.html)):

| Check | Result |
|-------|--------|
| Desktop (1100 px) | Table, badges and colours shown correctly |
| Phone (375 px) | Page doesn't scroll sideways (`scrollWidth` = `clientWidth`); the table scrolls inside its box |
| `<script>` hostname | Shown as the text `<script>alert(1)</script>`; no script ran |
| Server that never reported | "never" / "no results" |
| Stale server | Last-seen time in red |

```text
$ cargo test                                → 82 passed, 0 failed
$ cargo clippy --all-targets -- -D warnings → no warnings
$ cargo fmt --check                         → no changes
```

## Next step

Step 29 — dashboard route `GET /`: query the latest results per agent, fill
`DashboardView`, render `dashboard.html`.
