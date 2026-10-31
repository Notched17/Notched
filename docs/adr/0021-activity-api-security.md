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
  - An `Origin` or `Sec-Fetch-Site` header is refused (403). Browsers send one of them on every cross-site request; curl and scripts never do. (`Sec-Fetch-Mode` alone is allowed because Node's `fetch` sends it.)
  - `PUT`/`POST` need `Content-Type: application/json` (415), which forces a CORS preflight from a page. `OPTIONS` is 405 and sends no `Access-Control-*` headers, so the preflight fails.
- **Tokens.** `ntch_` + 32 random bytes (`SecRandomCopyBytes`), base64url. Shown once. Only the SHA-256 is kept (in the Keychain, `WhenUnlockedThisDeviceOnly`); the in-memory comparison checks every client without stopping early and compares in constant time. Unknown and revoked tokens give the same 401. A token needs no expiry because the user revokes it; revoking deletes the Keychain item, drops the client, and ends its activities.
- **Scopes** (`activity`, `banner`, `approval`, and the internal `claude`) are fixed when the client is created.
- **Limits.** Requests: 10/s per client, burst 20 (429 with `Retry-After`). Bad tokens: 20 a minute across all callers, after which bad tokens get 429 but valid ones are still served (so an attacker can't lock the user out). Request bodies ≤ 16 KB (256 KB for the Claude hook route only, which carries whole tool inputs), headers ≤ 8 KB, 3 s to send a request, 16 open connections. 5 live activities per client, alerts once per 30 s per client, banners 10 a minute.
- **No spoofing.** API activities are `.live` or `.passive` and always hideable, never `.system`. The expanded view names the client. Text is plain: control characters, bidi overrides and zero-width characters are removed and lengths capped, shown with `Text(verbatim:)`. Colours come from a fixed palette, symbols must be SF Symbol names, `openURL` must be http(s) and is only opened by a click.
- **A hand-written HTTP reader.** `HTTPRequestParser` handles one `Content-Length` request per connection and refuses chunked bodies, `Expect`, duplicate `Host`/`Content-Length`, and paths with anything but `[A-Za-z0-9-._/]`. It is pure and has a fuzz test. This is less code, and less surface, than pulling in an HTTP server.
- **No logging of secrets.** Tokens, bodies and text are never logged; only client ids and status codes.
- **`notched://banner` links** can't carry a token, so they can only show a banner, say "via link", are off by default, and are rate limited like timer links.
- **The server proves itself to the hook.** A stale `api.json` or a reused port could let another process answer `notched-hook`. The hook sends a random nonce; the gateway replies with `X-Notched-Proof` = HMAC-SHA256(nonce, key = SHA-256(token)); the hook prints a decision only if the proof matches. `api.json` is also deleted at launch, since a crash leaves it behind.
- **Starting is idempotent.** Registering three routes starts one listener; callbacks from a stale listener are ignored; `.ready` is only believed if the socket is on the configured port.
- **A Keychain read failure doesn't forget clients.** The client stays listed (its token stops working) so it can be revoked rather than silently vanishing.
- **Approval requests** are limited to one per 5 s per client (each one expands the island).
- **Link banners** can't choose a symbol or colour (always a link glyph, white), so a page can't imitate a system banner.
- **XPC** is skipped (optional in the roadmap).

## Consequences

- A local process of the same user that can read the Keychain or a token file can use the API. That is the same trust level as the user's own scripts; the token's job is to stop *unrelated* processes and web pages.
- The `Host` check means clients must connect to the loopback address or `localhost` (not a hostname alias).
- The port is random once and then stable. If it's taken, Settings says "Port … is already in use" rather than moving.

## To verify on the Mac

The listener's `requiredLocalEndpoint` is set to `127.0.0.1` with port `.any` and the port is passed to `NWListener(using:on:)`. Check `lsof -nP -iTCP -sTCP:LISTEN | grep Notched` shows `127.0.0.1:<port>` and not `*:<port>`; if the port binds on all interfaces, the peer check still refuses non-loopback connections, but the listener must be fixed.
