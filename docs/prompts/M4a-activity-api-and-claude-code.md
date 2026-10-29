We're continuing Notched. M1–M3b are done ✅ (confirm in `docs/ROADMAP.md`; if M3b isn't merged into `main`, stop and tell me). This is **M4a**: the expanded-tabs framework, the **Activity API**, and the **Claude Code** integration (#62 usage, #63 status plus approve/deny). It's the most "mine" part of the app, because it's how Claude Code shows up in the notch.

## Model guide (for me, not for you)
- Plan mode (Step 0) and the tab-host design (Step 1): Opus, high effort.
- Activity API security design and review (Step 2): Opus, xhigh effort. Its implementation: Sonnet, high effort.
- Hook helper and installer (Step 3): Sonnet, high effort, because a bad settings.json merge can break Claude Code.
- Usage parser tests and AI tab UI (Step 4): Sonnet, medium effort.
- Builds, tests and searches: Haiku via `build-runner` and `Explore`.

## Read first
1. `CLAUDE.md` (binding), especially security and permissions rules and Token economy.
2. `docs/ROADMAP.md` M4 rows **#62, #63, Activity API** (the others are M4b).
3. `docs/ISLAND-BEHAVIOR.md` §2 (activity model), §4 (regions), §7 (Activity API, Claude Code).
4. ADR-0006/0007, the M3a banner ADR, the "music stays primary" ADR, and the module reducer template.
5. Claude Code's **current** hooks documentation (fetch it; do not trust memory) and the real session logs on this Mac under `~/.claude/projects/` (inspect actual files).
6. Reference (read, adapt only if licensed): farouqaldori/vibe-notch (Apache-2.0). Do not copy anything without a compatible licence; attribute in `THIRD_PARTY_NOTICES.md`.

## Step 0: Plan (plan mode)
Propose a plan and wait for approval. Include the exact Activity API request/response schema, the security model, the hook installer's merge strategy, the permission/approval flow, the JSONL fields you found, reducer states and tests, and your **questions for me**.

## Step 1: Expanded tabs framework (small, needed by this and M4b)
- The expanded island currently pages between activities and Home. Add a **tab host** for module-provided tabs (e.g. "AI"), with a segmented, Apple-style tab bar that stays inside the island's width budget, keyboard navigation, VoiceOver labels, and Reduce Motion support. Modules register tabs through the module contract; tabs cost nothing when their module is off.
- Tests for tab registration/order; screenshot on notch and pill.

## Step 2: Activity API (a module of its own)
- **Transports:** `notched://` URL scheme for one-shots (e.g. banner, timer), and a **localhost-only** HTTP endpoint (bind 127.0.0.1 only, random or configurable port) for live updates. XPC is optional; skip unless trivial.
- **Security:** per-client **tokens** created in Settings; each client has a name, scopes (post activity, post banner, request approval) and can be revoked; tokens stored in Keychain; constant-time comparison; request size and rate limits; reject non-localhost `Host`/`Origin` (defends against DNS rebinding and web pages); off by default; no listening socket while disabled. Clients get a clear error for bad tokens.
- **Payloads:** a small set of templates mapping onto `LiveActivity` regions (title/subtitle/symbol/progress/tint/openURL/alert flag), with ids so a client can update and end its activity. Validate and clamp everything; untrusted text is never interpreted as markup.
- **Settings pane:** enable, port, list of clients with last-seen, revoke, "copy example curl".
- Tests: schema validation, auth failures, rate limiting, rebinding rejection, lifecycle (update/end/expire), and a fuzz-style test of malformed JSON.
- Docs: `docs/ACTIVITY-API.md` with examples (curl, a shell one-liner, a Raycast/Shortcuts example).

## Step 3: Claude Code status + approve/deny (#63)
- **Helper CLI** `notched-hook` (small, dependency-free; installed by the app into `~/.local/bin`), invoked by Claude Code hooks; sends events to the Activity API with a dedicated token, and for permission requests **waits for the reply** (with a timeout that falls back to Claude Code's normal prompt, so a closed Notched never blocks Claude Code).
- **Hook installer:** a one-click "Install Claude Code hooks" button that edits `~/.claude/settings.json` safely: back it up first, merge (never clobber existing hooks), keep it idempotent, and offer "Remove hooks" that restores exactly what was there. Show a diff preview before applying. Use the real current hook event names from the docs.
- **UI:** while Claude Code works, a `live` activity shows "Claude is working…" with the project name and a spinner glyph; multiple sessions are listed in the expanded view; when permission is needed the island **alert-expands** with the tool request (command or file path, truncated safely) and **Allow / Deny** (and "Allow once" vs. whichever options the hook protocol supports). A banner when the agent finishes. Never show secrets: redact obvious tokens/keys in displayed commands.
- Test with real Claude Code runs in a scratch directory; give me a numbered list for anything I must do.

## Step 4: Claude Code usage (#62)
- An "AI" tab showing today's and this week's token usage and estimated cost, and active sessions. **Local only, no login.** Parse the JSONL logs in `~/.claude/projects/` (check the real format first; handle format drift gracefully); FSEvents to watch for changes; incremental parsing (remember file offsets) so it stays cheap on huge logs.
- Pricing table in a data file (per-model, editable, with an "estimate" label). A unit-tested parser using real (sanitised) sample lines as fixtures.
- Plan-limit percentages are **optional and later**: don't read or store OAuth tokens. If you think there's a safe, documented route, ask me first.

## Verify
- Screenshots in `docs/screenshots/m4a/`: tab bar, AI tab, "Claude is working", approval request (allow/deny), finished banner, Activity API settings, notch and pill.
- Security checks: try the API without a token, with a wrong token, from a browser page, and with oversized payloads; confirm each is rejected. Kill Notched mid-approval: Claude Code must fall back to its own prompt.
- Robustness: sleep/wake, many sessions, a 100 MB log, hooks installed twice, settings.json with existing hooks and invalid JSON (refuse, don't clobber).
- Performance: idle < 0.5% CPU with the API enabled and no clients; memory < 150 MB.
- Update ROADMAP (✅/🟨 with measurements), write ADRs (API security model, hook protocol, usage parsing), `THIRD_PARTY_NOTICES.md`. Run a fresh-reviewer pass on the whole branch and fix critical/important findings.
- Final report: what was built, screenshots, numbers, what works on macOS 27.2, decisions, things for me to try, suggestions for M4b.

If any spec is impossible or wrong in practice, stop and tell me. Don't merge or push without asking.
