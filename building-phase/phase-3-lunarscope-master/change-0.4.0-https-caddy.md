# Change (0.4.0) — HTTPS with Caddy

**Repo:** `lunarscope-master` (new file `install/Caddyfile`)
**Date:** 2026-11-16
**Status:** Done — Caddyfile validated and tested with a real agent over
HTTPS; not committed yet

## Why

The master speaks plain HTTP and is meant to listen on `127.0.0.1` only
(step 32). Agents refuse plain HTTP to anything but localhost, and the
dashboard sends a session cookie marked `Secure`. So in real use something
has to do HTTPS in front of it. Until now that was only a sentence in the
docs. Caddy was chosen because it gets and renews certificates by itself
and needs a very short config.

```text
agents ──HTTPS (TLS 1.3)──▶ Caddy :443 ──HTTP──▶ lunarscope-master 127.0.0.1:3030 ──▶ SQLite
browser ─HTTPS────────────▶
```

## `install/Caddyfile`

```caddyfile
lunarscope.example.nl {
	tls {
		# Agents only speak TLS 1.3.
		protocols tls1.3
		# issuer internal
	}

	reverse_proxy 127.0.0.1:3030

	header {
		Strict-Transport-Security "max-age=31536000"
		X-Frame-Options "DENY"
		X-Content-Type-Options "nosniff"
		Referrer-Policy "same-origin"
		-Server
	}

	log {
		output file /var/log/caddy/lunarscope.log
	}
}
```

| Line | Why |
|------|-----|
| `protocols tls1.3` | The agent's HTTP client only allows TLS 1.3 (`tls_version_min`), so older versions are of no use and only widen what an attacker can try |
| `issuer internal` (commented) | For a name that isn't in public DNS: Caddy makes its own CA. Agents and browsers must then trust its root certificate |
| `reverse_proxy 127.0.0.1:3030` | The master on the same machine; it isn't reachable from outside |
| HSTS | Browsers keep using HTTPS for this name |
| `X-Frame-Options DENY` | The dashboard can't be put inside another site's frame (clickjacking on the admin buttons) |
| `nosniff`, `Referrer-Policy` | Small, standard hardening; the master didn't send these itself |
| `-Server` | Doesn't advertise the proxy software |

## Setting it up

1. Put the real name in place of `lunarscope.example.nl`.
2. Start the master with `--public-url https://<that name>`, so the install
   links point at Caddy and not at `127.0.0.1`.
3. `/etc/caddy/Caddyfile`, then `systemctl reload caddy`.
4. Public name (ports 80/443 open): Let's Encrypt, nothing else to do.
   Internal name: uncomment `issuer internal` and on every agent machine
   (before running the install link):

   ```bash
   sudo cp root.crt /usr/local/share/ca-certificates/caddy.crt
   sudo update-ca-certificates
   ```

   `root.crt` is `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`
   on the Caddy machine. The agent uses the system's trusted certificates
   (`rustls-platform-verifier`), so nothing in the agent changes.

## Tests

No code changed, so no new unit tests. Checks:

| Check | Result |
|-------|--------|
| `caddy validate` on `install/Caddyfile` (official `caddy:2` image) | ✅ Valid configuration |
| `caddy validate` on the test copy (internal CA, port 8443) | ✅ |

### End-to-end test

Caddy in a container (`--network host`) with a copy of the Caddyfile that
only differs in: name `lunarscope.test:8443`, `issuer internal`, the
temporary master on `127.0.0.1:3031`, log to stdout, and a global block
(`admin off`, `http_port 8080`) so it didn't take ports on the laptop.
Master started with `--public-url https://lunarscope.test:8443`. The
`lunarscope` service and the demo containers were not touched.

| Step | Result |
|------|--------|
| `curl --cacert root.crt https://lunarscope.test:8443/login` | `HTTP/2 200` with HSTS, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`; no `Server` header |
| Same with `--tls-max 1.2` | Refused (no connection) |
| `/healthz` over HTTPS | `{"status":"ok","version":"0.4.0"}` |
| Log in over HTTPS (user `admin`), "Add agent" for container `tls-test-01` | Install link `https://lunarscope.test:8443/install/…`; the script installed the agent with `master_url = "https://lunarscope.test:8443"` (container trusts Caddy's root certificate) |
| Agent run | `scan cycle: 4 finding(s) …; accepted 4, rejected 0, not sent 0` |
| Root certificate removed from the container, `--once` again | `invalid peer certificate: UnknownIssuer` — the agent doesn't fall back to unchecked TLS |

Test master, Caddy container and agent container were removed afterwards.

## Not done

- Caddy itself isn't installed on the laptop; the dev service keeps plain
  HTTP on `127.0.0.1:3030`, which the agents accept for localhost.
- A firewall rule so only Caddy's port is open is up to the server setup.
