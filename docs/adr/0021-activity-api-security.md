# ADR-0021: Activity API security model

- Status: accepted (M4a, built without a Mac to run it on; see "To verify")
- Date: 2026-10-30

## Context

Third-party tools need to put live activities, banners and approval requests in the island. The transport has to be reachable by scripts but not by web pages, other machines or other users' processes, and no client may be able to spoof a system alert or flood the island. Claude Code's hooks use the same door (ADR-0022).

Threats: (a) a web page in a browser on this Mac; (b) DNS rebinding; (c) another local process without a token; (d) a token holder that floods the island; (e) a client pretending to be the system.

## Decisions

- **One gateway, many modules.** `APIGateway` owns the checks. Modules register routes (`/v1/activities`, `/v1/banners`, `/v1/approvals` for the Activity API; `/v1/claude` for Claude Code). The `NWListener` exists only while a route is registered, so a disabled module has no socket (CLAUDE.md "a disabled module must cost zero").
- **Loopback only.** The listener's required local endpoint is `127.0.0.1`, and each accepted connection's peer is checked to be loopback again.
- **Order of checks:** Host/Origin guard → token → per-client rate limit → route → scope. Cheap and anonymous checks come first, and a refused browser request doesn't count as a failed login.
  - `Host` must be exactly `127.0.0.1:<port>` or `localhost:<port>` (421 otherwise). A DNS-rebinding page arrives with its own hostname.
  - Any `Origin` or `Sec-Fetch-*` header is refused (403). Browsers always send them on fetch and form posts; curl and scripts never do.
  - `PUT`/`POST` need `Content-Type: application/json` (415), which forces a CORS preflight from a page. `OPTIONS` is 405 and sends no `Access-Control-*` headers, so the preflight fails.
- **Tokens.** `ntch_` + 32 random bytes (`SecRandomCopyBytes`), base64url. Shown once. Only the SHA-256 is kept (in the Keychain, `WhenUnlockedThisDeviceOnly`); the in-memory comparison checks every client without stopping early and compares in constant time. Unknown and revoked tokens give the same 401. A token needs no expiry because the user revokes it; revoking deletes the Keychain item, drops the client, and ends its activities.
- **Scopes** (`activity`, `banner`, `approval`, and the internal `claude`) are fixed when the client is created.
- **Limits.** Requests: 10/s per client, burst 20 (429 with `Retry-After`). Bad tokens: 20 a minute across all callers, after which bad tokens get 429 but valid ones are still served (so an attacker can't lock the user out). Request bodies ≤ 16 KB, headers ≤ 8 KB, 5 s to send a request, 16 open connections. 5 live activities per client, alerts once per 30 s per client, banners 10 a minute.
- **No spoofing.** API activities are `.live` or `.passive` and always hideable, never `.system`. The expanded view names the client. Text is plain: control characters, bidi overrides and zero-width characters are removed and lengths capped, shown with `Text(verbatim:)`. Colours come from a fixed palette, symbols must be SF Symbol names, `openURL` must be http(s) and is only opened by a click.
- **A hand-written HTTP reader.** `HTTPRequestParser` handles one `Content-Length` request per connection and refuses chunked bodies, `Expect`, duplicate `Host`/`Content-Length`, and paths with anything but `[A-Za-z0-9-._/]`. It is pure and has a fuzz test. This is less code, and less surface, than pulling in an HTTP server.
- **No logging of secrets.** Tokens, bodies and text are never logged; only client ids and status codes.
- **`notched://banner` links** can't carry a token, so they can only show a banner, say "via link", are off by default, and are rate limited like timer links.
- **XPC** is skipped (optional in the roadmap).

## Consequences

- A local process of the same user that can read the Keychain or a token file can use the API. That is the same trust level as the user's own scripts; the token's job is to stop *unrelated* processes and web pages.
- The `Host` check means clients must connect to the loopback address or `localhost` (not a hostname alias).
- The port is random once and then stable. If it's taken, Settings says "Port … is already in use" rather than moving.

## To verify on the Mac

The listener's `requiredLocalEndpoint` is set to `127.0.0.1` with port `.any` and the port is passed to `NWListener(using:on:)`. Check `lsof -nP -iTCP -sTCP:LISTEN | grep Notched` shows `127.0.0.1:<port>` and not `*:<port>`; if the port binds on all interfaces, the peer check still refuses non-loopback connections, but the listener must be fixed.
