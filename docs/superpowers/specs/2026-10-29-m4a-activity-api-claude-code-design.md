# M4a Activity API and Claude Code: design

Status: **approved (Step 0, 30 Oct 2026).** Charlie took the recommended answer to every question in §9. Step 1 (the expanded tab host, ADR-0020) is already merged (`main` = `3d8b190`, PR #3).

Binding sources: `docs/prompts/M4a-activity-api-and-claude-code.md`, `CLAUDE.md`, ROADMAP M4 rows #62, #63 and "Activity API", ISLAND-BEHAVIOR §2/§4/§7, ADR-0006/0007/0011/0012/0020, `docs/templates/module-reducer.md`.

**How this session works.** It runs in a Linux cloud container: no Swift toolchain, no Xcode, no macOS, and none of your real `~/.claude/projects` logs. You chose "plan, then write code blind". So I'll write the code and the tests, but I can't build them, and I can't take screenshots or do any of the Verify section. Expect one round of compile fixes on the Mac, and treat every 🟨 in this document as "check on the Mac".

---

## 1. What I found

### 1.1 Claude Code hooks (code.claude.com/docs/en/hooks, fetched 29 Oct 2026)

- **Settings shape:** `hooks → EventName → [ { "matcher"?: string, "hooks": [ { "type": "command", "command": …, "args"?: [...], "timeout"?: s, "async"?: bool, "onFailure"?: … } ] } ]`. With `args`, `command` is run directly, with no shell. That's what we want: no quoting problems with spaces in paths.
- **Command timeout:** defaults to 600 s, lowered to 30 s on `UserPromptSubmit`. `SessionEnd` gets 1.5 s. Matching hooks run in parallel. An identical handler defined in two settings files runs once.
- **Common input:** `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, plus `agent_id`/`agent_type` in subagents.
- **Events we use:**

  | Event | Input we read | Why |
  |---|---|---|
  | `SessionStart` | `source`, `model`, `session_title` | Registers the session (project = basename of `cwd`) |
  | `UserPromptSubmit` | `session_title` (never `prompt`) | → working |
  | `PermissionRequest` | `tool_name`, `tool_input`, `permission_suggestions`, `mcp_server` | → approval |
  | `Notification` | `notification_type` (`idle_prompt`, `permission_prompt`), `message` | → waiting for input; dismisses our approval card if answered in the terminal (see 🟨 Q-A) |
  | `Stop` | – | → finished banner, idle |
  | `StopFailure` | `error` | → "Claude stopped: rate limit" banner |
  | `SessionEnd` | `reason` | → end the activity |

  Not used: `PreToolUse`/`PostToolUse`. They would let us show "Running Bash…", but they cost one process spawn per tool call. I'm asking you about this (§9 Q4).
- **PermissionRequest reply** (stdout, exit 0):
  - Allow: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
  - Always allow: the same, plus `"updatedPermissions":[<one of the permission_suggestions, echoed>]`. The docs allow echoing a suggestion; Claude Code applies it, and Notched never writes permission rules itself.
  - Deny: `"decision":{"behavior":"deny","message":"Denied from Notched"}`. Optionally `"interrupt":true` ("Deny and stop").
  - **No output, exit 0 = no decision, so Claude Code shows its normal prompt.** Exit 2 is ignored for this event. A hook killed by its timeout renders no decision either. Every failure path in `notched-hook` therefore ends with "print nothing, exit 0", which is the fallback the prompt asks for.
  - Deny and ask rules still win over our "allow" (Claude Code's own safety holds).
- **Workspace trust:** Claude Code holds back hooks until the folder is trusted, so an untrusted repo gets no island approval. That's correct behaviour.

### 1.2 Session logs (real JSONL, Claude Code 2.1.312 in this container)

- Path: `<config>/projects/<cwd with / → ->/<session-uuid>.jsonl`. Subagents write to `<session-uuid>/subagents/agent-<id>.jsonl`, and those must be counted too (they cost tokens).
- Line `type`s seen: `assistant`, `user`, `attachment`, `ai-title`, `last-prompt`, `queue-operation`, `tools-used`, `atis-latch`. Only `assistant` carries usage. Unknown types are skipped.
- An `assistant` line has `timestamp` (ISO-8601, UTC, fractional seconds), `sessionId`, `cwd`, `requestId`, `isSidechain`, `version`, and `message.{id, model, usage}`.
- `message.usage`: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `cache_creation.{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}`, `service_tier`, `speed`, plus `iterations[]`, `server_tool_use`, and `output_tokens_details`.
- **Duplicates:** one response is written as one line per content block. In this session's log, 9 of 13 responses appeared on 2–3 lines, each with identical `usage`. **We dedupe by `message.id` (+ `requestId`)**, as ccusage does.
- **Format drift:** every field is optional. A line that doesn't decode is counted in a "skipped lines" diagnostic and ignored. A missing 5m/1h split counts all cache writes as 5m. An unknown model is shown as "unpriced" tokens, never as $0.
- Older logs may live under `~/.config/claude/projects`, and `CLAUDE_CONFIG_DIR` can move both. We watch `~/.claude/projects` and `~/.config/claude/projects` if they exist. A GUI app doesn't see your shell's `CLAUDE_CONFIG_DIR`, so a custom path is a setting.

### 1.3 vibe-notch

Not read yet. I'll study its hook ↔ app flow before writing the CLI and copy nothing; any adapted idea gets attributed. Apache-2.0 is compatible with GPL-3.0.

---

## 2. Shape of the work

```
Sources/Services/LocalAPI/          the server, shared by both modules (pure parts tested)
  HTTPRequestParser.swift           pure: request line, headers, Content-Length body; limits
  LocalAPIGuard.swift               pure: Host/Origin/Sec-Fetch/Content-Type checks
  APIToken.swift                    pure: format, SHA-256, constant-time compare
  APIClients.swift                  client records (UserDefaults) + KeychainTokenStore
  TokenBucket.swift                 pure rate limiter (per client, per failure source)
  LocalAPIServer.swift              NWListener on 127.0.0.1; connection lifecycle; dispatch
  APIDiscoveryFile.swift            ~/Library/Application Support/Notched/api.json (0600): port only
Sources/Modules/ActivityAPI/        third-party activities (module "Activity API")
  ActivityPayload.swift             pure: decode + validate + clamp
  ActivityAPIReducer.swift          pure: per-client activities, expiry, alert limits, approvals
  ActivityAPIModule.swift           shell
  ActivityAPIPresentation.swift     templates → LiveActivity regions
  ActivityAPISettingsPane.swift     enable, port, clients, revoke, copy curl
Sources/Modules/ClaudeCode/         #62 + #63 (module "Claude Code")
  ClaudeHookEvent.swift             pure: hook stdin JSON → typed event
  ClaudeSessionsReducer.swift       pure: sessions, approvals queue, banners
  ToolRequestSummary.swift          pure: tool_input → one safe line (+ SecretRedactor)
  SecretRedactor.swift              pure
  ClaudeSettingsMerger.swift        pure: install/remove hooks in settings.json (+ OrderedJSON)
  OrderedJSON.swift                 pure: order-preserving JSON parse/print
  LineDiff.swift                    pure: diff for the preview sheet
  ClaudeUsageParser.swift           pure: JSONL line → UsageRecord
  ClaudeUsageAggregator.swift       pure: dedupe, day buckets, cost
  ClaudePricing.swift + claude-pricing.json
  ClaudeUsageService.swift          actor: FSEvents, file offsets, incremental reads
  ClaudeCodeModule.swift            shell
  ClaudeCodeViews.swift             compact/minimal/expanded, approval card
  ClaudeAITab.swift                 the "AI" tab
  ClaudeCodeSettingsPane.swift      install/remove hooks + diff preview, usage options
  HookInstaller.swift               file IO around the merger: backup, atomic write, CLI copy
Tools/notched-hook/main.swift       the helper CLI (Foundation only), XcodeGen `tool` target
```

The two modules share **one server** (`LocalAPIServer`), which runs while either module is on. With only Claude Code on, it accepts only Claude Code's own client (§9 Q1).

---

## 3. Activity API: transport

- **Listener:** `NWListener` with `requiredLocalEndpoint = 127.0.0.1:<port>`. Never `0.0.0.0`, never IPv6 any. The port is picked at random (49152–65535) the first time the server is turned on, then saved and shown in Settings, where it can be changed. A random-but-stable port keeps the curl examples valid and avoids clashes. If the port is taken, the server shows "Port in use" in Settings; it never silently moves.
- **No listening socket while both modules are off.** The listener is created in `start()` and cancelled in `stop()`.
- **Discovery:** `api.json` = `{"version":1,"port":N}`, mode 0600, removed on stop. It holds no token. `notched-hook` reads it, so a port change needs no re-install.
- **HTTP subset (hand-rolled, pure, tested):** HTTP/1.1 only, `Connection: close` (one request per connection), no chunked encoding, no `Expect: 100-continue`. Limits:
  - headers ≤ 8 KB
  - body ≤ 16 KB (`Content-Length` required for bodies)
  - 5 s to receive the whole request
  - at most 16 open connections; extras are refused at accept time
  - responses are always `application/json; charset=utf-8`
- **XPC:** skipped, as the prompt allows.

## 4. Activity API: security model (→ ADR-0021)

Threats: (a) a web page in a browser on this Mac, (b) DNS rebinding, (c) another local process without a token, (d) a token holder who floods the island, (e) display spoofing (a client pretending to be a system alert).

| Defence | Detail |
|---|---|
| Loopback only | Bound to 127.0.0.1; a remote host can't connect. |
| Off by default | No socket unless a module that needs it is on. |
| **Host check** (b) | `Host` must be exactly `127.0.0.1:<port>` or `localhost:<port>`. Anything else → 421 `bad_host`. A rebinding attack arrives with the attacker's hostname. |
| **Origin/Fetch check** (a) | Any `Origin` header, or any `Sec-Fetch-Site`/`Sec-Fetch-Mode` header → 403 `browser_forbidden`. curl, scripts and our CLI never send these; browsers always do on fetch and form posts. |
| Content-Type (a) | Writes need `Content-Type: application/json` exactly, which forces a CORS preflight. `OPTIONS` → 405 with no `Access-Control-*` headers, so the preflight fails. |
| **Per-client tokens** (c) | `Authorization: Bearer ntch_<43 chars base64url of 32 random bytes>` (`SecRandomCopyBytes`). The token is shown once at creation with a copy button. Stored in the **Keychain** (generic password, service `me.rkck.Notched.api`, account = client id). The app keeps only SHA-256 hashes in memory and compares them in **constant time** (a fixed-length XOR fold). |
| Scopes | `activity` (post/update/end), `banner`, `approval`. Each endpoint checks its scope → 403 `missing_scope`. |
| Revoke | Deletes the Keychain item and the record and ends that client's activities at once. |
| Clear errors | 401 `missing_token` / `invalid_token` (the same message for an unknown token and a revoked one). Never reveals which clients exist. |
| **Rate limits** (d) | Per client: token bucket of 10 requests/s, burst 20 → 429 with `Retry-After`. Failed auth: across all sources, 20 failures/min → 429 for everyone else's bad tokens for a minute; valid tokens keep working. At most 5 live activities per client → 409 `too_many_activities`. Alerts: 1 per client per 30 s; extra alerts are applied as plain updates. Banners go through `BannerSource` (ADR-0012). |
| **No spoofing** (e) | API activities are only `.live` or `.passive`, always hideable, and can't be `system`. Every API activity's expanded view says which client posted it ("from Raycast"). Text is shown with `Text(verbatim:)`, never markdown or `AttributedString`. Control and bidi-override characters are stripped. Symbols must exist (`NSImage(systemSymbolName:)`) or fall back to `app.badge`. Tints come from a fixed palette of names. `openURL` must be `https` or `http`, and is opened only by a click. |
| Logging | Never logs tokens, bodies or text. Logs client ids and status codes at `.info`. |

## 5. Activity API: schema (v1) → `docs/ACTIVITY-API.md`

All endpoints are under `/v1`. Errors: `{"error":{"code":"invalid_payload","message":"title is required","field":"title"}}`.

**Post or update an activity:** `PUT /v1/activities/{id}` (scope `activity`). `id` is 1–64 characters of `[A-Za-z0-9._-]`, scoped to the client, so two clients can both use `build`.

```json
{
  "template": "status",            // "status" | "progress" | "countdown"
  "title": "Deploy",               // required, ≤ 40 chars after trimming
  "subtitle": "Uploading assets",  // optional, ≤ 80
  "symbol": "arrow.up.circle.fill",// optional SF Symbol, default per template
  "tint": "blue",                  // optional: one of the palette names, else white
  "progress": 0.42,                // "progress": required, clamped to 0…1
  "endsAt": "2026-10-29T10:30:00Z",// "countdown": required, 1 s…24 h ahead
  "trailing": "42%",               // optional short compact-trailing text, ≤ 8 chars
  "openURL": "https://ci.example.com/run/42",  // optional, http(s) only
  "alert": false,                  // optional: expand briefly (rate-limited)
  "kind": "live",                  // optional: "live" (default) | "passive"
  "staleAfter": 600,               // optional seconds, 10…14400, default 600
  "expiresAfter": 3600             // optional seconds, 60…28800, default 3600: ends if not updated
}
```
→ `201 {"id":"deploy","state":"active"}` when created, `200` when updated.

- **Regions.** status: symbol leading, `trailing` text or nothing; minimal = symbol. progress: symbol leading, a ring trailing (the ring alone in minimal); the expanded view adds a bar. countdown: symbol leading, a system-ticked timer trailing (as in Timers), a ring in minimal. Expanded: title, subtitle, "from <client>", and an "Open" button if there's a URL.
- **End:** `DELETE /v1/activities/{id}` → 204. An optional `?dismiss=immediate` skips Recent.
- **List:** `GET /v1/activities` → this client's live activities (ids and states).
- **Banner:** `POST /v1/banners` (scope `banner`) `{"title":…, "subtitle":…, "symbol":…, "tint":…}` → 202. It may be dropped by the banner rate limit; the response says `{"queued":true}` either way.
- **Approval:** `POST /v1/approvals` (scope `approval`) `{"title":…, "detail":…, "symbol":…, "options":["allow","deny"], "timeout":60}`. This is a long poll: the connection stays open until the user picks, or until `timeout` (5–120 s), then → `200 {"decision":"allow"|"deny"|"timeout"|"dismissed"}`. One open approval per client (a second → 409).
- **Errors:** 400 `invalid_json`/`invalid_payload`, 401, 403, 404 `not_found`, 405, 409, 411 `length_required`, 413 `too_large`, 415 `unsupported_media_type`, 421 `bad_host`, 429 `rate_limited`, 503 `disabled` (a module turned off mid-request).
- **URL scheme (one-shots), extended:** `notched://banner?title=…&subtitle=…&symbol=…`. It's rate-limited like timer links. Any app or page can open it, so it has no token: it's a banner only, shown with a "via link" subtitle so it can't pose as a real system banner, and off unless "Allow banners from links" is on (default off). Live activities need the HTTP API.

## 6. Claude Code status and approvals (#63, → ADR-0022 hook protocol)

### 6.1 `notched-hook` CLI

- A Swift `tool` target (Foundation only), shipped in `Notched.app/Contents/Helpers/notched-hook`, signed with the app.
- "Install hooks" **copies** it to `~/.local/bin/notched-hook` (creating the directory, mode 0755). The copy is refreshed whenever the app's bundled version differs (`notched-hook --version`). A copy survives the app moving, and settings.json then points at a stable path.
- **Token:** Claude Code gets its own API client, "Claude Code" (scopes: `claude`, internal). Its token is written to `~/Library/Application Support/Notched/claude-hook.token` with mode 0600. Not the Keychain: a CLI reading the app's Keychain item triggers access prompts, and the Keychain wouldn't protect against anything here. A process that can read a 0600 file in your home can already edit `~/.claude/settings.json` and run anything as you. The token only lets you post Claude status and *ask* for approvals; it can't answer them (§9 Q2).
- **Flow:** read stdin (≤ 256 KB, else exit 0 silently) → read `api.json` + the token → `POST http://127.0.0.1:<port>/v1/claude/hook`, with the hook JSON as the body, forwarded verbatim (the app does all the parsing, which is testable) → print the response body to stdout only if it's a 200 with a JSON body → exit 0.
- **Every failure prints nothing and exits 0:** Notched not running (connection refused), no `api.json`, a bad token, a timeout, a 5xx. So Claude Code continues normally, or shows its own permission prompt. Nothing goes to stderr except with `NOTCHED_HOOK_DEBUG=1`.
- **Timeouts:** non-approval events use a 2 s request timeout and return immediately (the app replies 204 right away). For `PermissionRequest`, the request waits up to **`approvalWait`** (default 90 s, set in Settings, 15–300 s). The hook entry's own `timeout` is `approvalWait + 30`, so the CLI always exits cleanly before Claude Code kills it.
- **The approval reply is built by the app** from the user's choice, in exactly the shape in §1.1. The CLI never interprets it.
- **Kill Notched mid-approval** → the connection drops → the CLI prints nothing → Claude Code shows its prompt. That's the Verify-section test.

### 6.2 Hook installer (pure `ClaudeSettingsMerger` + IO `HookInstaller`)

- **Our entries.** For each event in §1.1: `{"hooks":[{"type":"command","command":"/Users/<you>/.local/bin/notched-hook","args":["<Event>"],"timeout":T}]}`. There's no matcher, so every tool counts for `PermissionRequest`. We recognise our own entries by `command` ending in `/notched-hook`; nothing else is ever touched.
- **Order-preserving JSON** (`OrderedJSON`): your keys, other hooks and formatting order stay as they were. Output uses 2-space indentation; the diff preview shows any whitespace change honestly.
- **Install:**
  1. Read `~/.claude/settings.json`. A missing file → `{}`. **Invalid JSON → refuse** with the parse error and the line; never write.
  2. If `hooks` exists but isn't an object, or an event's value isn't an array → refuse.
  3. Remove any existing entries of ours, then append ours to each event's array. Groups belonging to others are untouched. That makes install idempotent: installing twice gives byte-identical output.
  4. Show the **diff preview** (a sheet with a unified line diff) → Apply.
  5. **Back up** to `~/.claude/settings.json.notched-backup-<ISO date>`, keeping the newest 5, and record the backup's path plus the SHA-256 of the file we wrote.
  6. Write atomically (temp file in the same directory + `rename`) through a symlink if settings.json is one (dotfile managers), keeping the file's mode. Re-read and re-parse after writing to check it.
- **Remove:**
  - If settings.json still hashes to what we wrote → restore the backup **byte-for-byte**. That's "exactly what was there".
  - Otherwise (you edited it since) → remove only our entries, drop groups and events that became empty only because of us, and drop `hooks` if we created it and it's now empty. The diff preview comes first here too.
- **Refuse rather than guess:** a file that changed between the preview and Apply (a hash check) → re-preview.
- **Status in Settings:** "Installed", "Not installed", "Installed, CLI out of date", or "Partly installed (edited)", re-read when the pane opens. Project-level `.claude/settings*.json` files aren't touched.

### 6.3 `ClaudeSessionsReducer` (pure)

```
State: sessions[id] = { project, title?, phase, lastEvent, startedWorkingAt? }
       approvals: FIFO of { approvalID, sessionID, summary, options }   (one shown at a time)
phase: idle | working | waitingForApproval | waitingForInput | finished(at)

Events: hook(ClaudeHookEvent, receivedAt) | approvalAnswered(id, Decision)
        | approvalConnectionClosed(id) | tick
Effects: post(SessionSnapshot) | end(sessionID) | alert(sessionID) | banner(ClaudeBanner)
         | reply(approvalID, HookReply?) | wake(Date)
```

Rules:
- `SessionStart` → idle, with no activity yet (a session sitting at the prompt isn't news). `UserPromptSubmit` → working: post a `.live` activity, "Claude is working…" + project.
- `PermissionRequest` → waitingForApproval. Queue the approval. If it's at the front: post with **alert** (the island expands), and the expanded view becomes the approval card.
- Answer → `reply(...)` → working. The next queued approval alerts.
- `approvalConnectionClosed` (the CLI timed out, Claude Code killed it, or the terminal answered) → drop it from the queue silently. No reply.
- `Notification(permission_prompt)` while an approval is shown → keep the card; it only means the terminal prompt is also visible.
- `Notification(idle_prompt)` → waitingForInput: the activity says "Waiting for you", with no banner.
- `Stop` → finished. Banner "Claude finished · <project>" (through `BannerSource`, keyed per session; at most one per session per 20 s), but only if the session worked ≥ 10 s (§9 Q5), so quick answers don't flash the island. The activity ends after 8 s (`.default` dismissal, so it shows under Recent).
- `StopFailure` → banner "Claude stopped · rate limit", then idle.
- `SessionEnd` → end with immediate dismissal. Any of its queued approvals are dropped.
- Watchdog: working with no event for 15 min → stale ("No word from Claude Code"). 60 min → end. A dead terminal never leaves the island stuck.
- Subagent events (`agent_id` present) count towards their parent session.
- Ranking: `.live`, relevance 0.5. Waiting for approval → relevance 1.0 (still under media, ADR-0011, but it alerts).
- Several sessions → several activities, listed by the coordinator. Two working sessions in the same project are labelled "Notched (2)".

**Approval card (expanded):**
- Leading: the Claude glyph (an SF Symbol: `sparkle`, no logo). Title "Allow Bash?". Project name.
- Center: the request on one or two lines, monospaced, truncated in the middle.
- Bottom: **Deny** · **Allow** (`.glassProminent`), plus a "⋯" menu with **Always Allow** (only when `permission_suggestions` has an `addRules` entry; its label shows the rule, e.g. "Always allow `Bash(npm test)`"), **Deny and Stop**, and **Answer in Terminal** (replies with no decision, so Claude Code's prompt takes over).
- Keyboard while the panel has focus: ⏎ Allow, ⌘⌫ Deny, Esc collapses (no reply).
- The card never takes focus by itself.
- VoiceOver announces "Claude Code wants to run a command in Notched".

**`ToolRequestSummary` + `SecretRedactor`:**
- Bash → the `command`. Edit/Write/Read/NotebookEdit → `file_path`, made relative to `cwd` (`~` for home). WebFetch → the URL host + path. WebSearch → the query. MCP → `server › tool`. Anything else → the tool name + its first string field.
- Redact before truncating:
  - `sk-ant-…`, `sk-…`, `ghp_/gho_/ghs_/github_pat_…`, `xox[abpr]-…`, `AKIA[0-9A-Z]{16}`, `AIza…`, JWTs (`eyJ…\.eyJ…\.…`)
  - `Bearer <x>`, `Authorization: <x>`, `--password[= ]x`, `-p<x>` for mysql
  - `(?i)[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|PRIVATE_KEY)[A-Z0-9_]*=<x>`
  - `://user:pass@`, and `-----BEGIN … PRIVATE KEY-----` blocks
  - long high-entropy runs (≥ 32 base64/hex characters) → `••••`
- Truncate to 160 characters with a middle ellipsis. Newlines → `⏎`.
- This is display-only. The real request goes to Claude Code untouched.

## 7. Claude Code usage (#62, → ADR-0023 usage parsing)

- **`ClaudeUsageParser`** (pure): line `Data` → `UsageRecord { messageID, requestID?, timestamp, model, input, output, cacheWrite5m, cacheWrite1h, cacheRead, sessionID, projectPath }`, or nil (not `assistant`, no usage, synthetic model `<synthetic>`). Fixtures: real lines from this container's logs, sanitised (ids randomised, content blocks emptied, paths replaced), plus hand-made drift cases (no `cache_creation`, a string number, an unknown type, a truncated line, a BOM, CRLF).
- **`ClaudeUsageAggregator`** (pure): dedupe by `messageID + requestID`, using a set kept only for records inside the window. Buckets by **local calendar day × model**. Today = the local day. **This week = the last 7 days including today** (§9 Q6). Cost per bucket from `ClaudePricing`; models without a price are shown as "unpriced tokens".
- **`claude-pricing.json`** (a resource), overridable by `~/Library/Application Support/Notched/claude-pricing.json`:
  `{"version":1,"updated":"2026-10-29","models":[{"match":"claude-opus-5-5*","input":…, "output":…, "cacheWrite5m":…, "cacheWrite1h":…, "cacheRead":…}]}`, in USD per million tokens. The longest matching prefix wins. The UI always says "≈ $x.xx estimated (API prices)", because subscription users don't pay per token. Before committing, I'll check the prices against the `claude-api` skill's current table.
- **`ClaudeUsageService`** (actor):
  - FSEvents on the projects folder(s) (file events, 2 s latency), created while the module is on.
  - Per file: `{inode, offset, pendingPartialLine}`. Read new bytes from `offset`. Parse only complete lines. If the inode changes or the size shrinks → reread from 0.
  - Launch: only files with mtime ≥ the window start (8 days) are read, in 1 MB chunks at utility QoS. A 100 MB log streams through without being loaded whole.
  - **Lazy:** FSEvents only marks files dirty. Parsing happens when the AI tab becomes visible (`onVisibilityChange`), or at most every 5 min through `RefreshScheduler` while today's totals are shown somewhere. With the tab closed and no activity, nothing is parsed, so idle cost is zero.
- **AI tab:**
  - Today and This week: tokens (in / out / cache) and ≈ cost.
  - A 7-day bar row.
  - Top models.
  - **Active sessions:** from the hooks if installed. Otherwise, files written in the last 5 min, labelled with their project.
  - The tab is registered via `setTabs` only while the usage sub-feature is on.
- **No OAuth, no network, no credentials.** Plan-limit percentages are out of scope.

## 8. Modules, settings, tests

- **"Activity API" module** (`activityapi`, off by default, no permission). Settings:
  - enable (= the module switch)
  - port
  - "Allow banners from links"
  - a clients list (name, scopes, created, last seen, Revoke)
  - "New client…" (name + scopes → token shown once)
  - "Copy example curl" (real port, a `$NOTCHED_TOKEN` placeholder; never the token itself)
- **"Claude Code" module** (`claudecode`, off by default, no TCC permission). Two sub-switches: **Status & approvals** (needs hooks: install button, diff preview, remove, status, approval wait) and **Usage tab** (projects folder, pricing note). Turning the module off stops the server's Claude client, removes its tab, and leaves the hooks installed but harmless: the CLI finds no server and exits 0.
- **Tests** (Swift Testing, Foundation-only reducers):
  - `HTTPRequestParserTests`: limits, partial reads, malformed, fuzz
  - `LocalAPIGuardTests`: Host variants, Origin, Sec-Fetch, rebinding hostnames
  - `APITokenTests`: format, hash, constant-time equality
  - `TokenBucketTests`
  - `ActivityPayloadTests`: every field's validation and clamping, control characters, a fuzz test of random bytes and mutated JSON (never crashes, always a 4xx)
  - `ActivityAPIReducerTests`: create/update/end/expire/stale, per-client caps, alert limit, revoke, approval timeout
  - `ClaudeHookEventTests`
  - `ClaudeSessionsReducerTests`: the flows above, queue order, closed connections, watchdog, sleep/wake
  - `ToolRequestSummaryTests` / `SecretRedactorTests`
  - `ClaudeSettingsMergerTests`: empty, missing file, existing hooks for the same event, other events, invalid JSON, a non-object `hooks`, install twice = identical, remove after install = identical bytes, remove after a user edit, key order preserved
  - `OrderedJSONTests`: round-trips, unicode escapes, numbers
  - `LineDiffTests`
  - `ClaudeUsageParserTests` (fixtures) / `ClaudeUsageAggregatorTests`: dedupe, day boundaries across time zones, pricing match, unpriced
  - `ExpandedTabs` registration and order: already covered by Step 1.
- **ADRs:** 0021 Activity API security model, 0022 Claude Code hook protocol, 0023 usage parsing.
- **Also:** `docs/ACTIVITY-API.md`, `THIRD_PARTY_NOTICES.md` (vibe-notch, if anything is adapted), and ROADMAP rows.

## 9. Questions for Charlie

**Charlie's decisions (30 Oct):**
- Q1: yes, one switch.
- Q2: a 0600 token file.
- Q3: 90 s.
- Q4: no tool detail, so no `PreToolUse` hooks.
- Q5: the banner shows only after ≥ 10 s of work.
- Q6: the last 7 days.

1. **Shared server:** may the localhost server run for Claude Code even when the third-party "Activity API" module is off? I recommend yes: then Claude Code needs one switch, not two.
2. **Hook token:** a 0600 file in Application Support (recommended, reasoning in §6.1), or the Keychain (expect access prompts from the CLI)?
3. **Approval wait:** 90 s on the island before falling back to the terminal prompt?
4. **"Running Bash…" detail:** add async `PreToolUse` hooks (one short process per tool call, ~10 ms each), or keep it to "Claude is working…" (recommended for the CPU budget)?
5. **Finished banner:** only after ≥ 10 s of work, or after every turn?
6. **"This week":** the last 7 days (recommended), or the calendar week from your locale's first weekday?

🟨 **To check on the Mac (can't be known from the docs):**
- **A:** Does Claude Code show its terminal prompt *while* a `PermissionRequest` hook is still running, or only after the hook returns? If only after, a user at the terminal waits up to 90 s, and "Answer in Terminal" plus a shorter wait become essential.
- **B:** When you answer in the terminal, does Claude Code kill our hook (we'd see the connection close and remove the card)?
