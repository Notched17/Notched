# ADR-0022: Claude Code hook protocol

- Status: accepted (M4a, built without a Mac to run it on)
- Date: 2026-10-30
- Source: the current hooks reference, https://code.claude.com/docs/en/hooks (read 29 Oct 2026)

## Context

Notched shows Claude Code's work and answers its permission requests (#63). Claude Code runs a command for each hook event and passes JSON on stdin. A closed or slow Notched must never block Claude Code.

## Decisions

- **Events:** `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SessionEnd`. Not `PreToolUse`/`PostToolUse`: they'd start a process for every tool call and add only a "Running Bash…" line (Charlie chose not to).
- **`PermissionRequest`, not `Notification`.** The docs say to use `PermissionRequest` to run a hook when Claude asks for permission; `Notification`/`permission_prompt` only fires after about six seconds.
- **Reply format** (stdout, exit 0), built by the app in `ClaudeHookReply`:
  - allow: `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
  - always allow: the same plus `"updatedPermissions":[<one of the request's permission_suggestions, echoed>]`. Notched never writes permission rules itself.
  - deny: `"decision":{"behavior":"deny","message":"Denied from Notched"}`, with `"interrupt":true` for "Deny and stop".
- **No decision = print nothing, exit 0.** Claude Code then shows its own prompt. (Exit 2 is ignored for this event, so it can't be used.) `notched-hook` does this on every failure: Notched not running, no port file, no token, a timeout, a non-200 reply, a bad reply. Claude Code's "deny and ask rules still apply" holds too.
- **`notched-hook`** is a Foundation-only tool in `Contents/MacOS`, copied by the installer to `~/.local/bin/notched-hook`. It reads the hook JSON (≤ 256 KB), the port from `~/Library/Application Support/Notched/api.json`, and a token from `claude-hook.token`, then `POST`s to `/v1/claude/hook`. Non-approval events time out in 2 s; a permission request waits up to 330 s for the app's own timer (default 90 s, 15–300 s), and the hook entry's `timeout` is that wait + 30 s so Claude Code never kills it first.
- **The hook verifies the server** (nonce → `X-Notched-Proof`, ADR-0021) before printing a decision, so an impostor on the port can't approve anything.
- **No waiting behind an invisible card.** If the island is paused, the screen is locked or asleep, or no island is on screen, a permission request returns "no decision" at once and Claude Code asks in the terminal.
- **The token is a 0600 file**, not a Keychain item: a command-line tool reading the Keychain triggers access prompts, and the file is readable only by the user, who could already edit `settings.json`. The token's scope is `claude`: it can post hook events and cause an approval card to be shown. It cannot answer one.
- **Hook entries:** `{"hooks":[{"type":"command","command":"/Users/you/.local/bin/notched-hook","args":[],"timeout":N}]}` for each event, no matcher. `args: []` makes Claude Code run the file directly (no shell, so no quoting problems); older versions that ignore `args` run the same path. The helper reads the event name from the JSON, so it needs no argument.
- **Installer** (`ClaudeSettingsMerger` + `HookInstaller`): validates the new text with a second parser before writing, reads it back and puts the old file back if it differs, never prunes the backup that Remove restores from; edits only entries whose command ends in `/notched-hook`; keeps the user's keys, order and other hooks (`OrderedJSON`); refuses invalid JSON and unexpected shapes; shows a diff first; refuses if the file changed since the preview; backs up to `settings.json.notched-backup-<time>` (newest 5 kept); writes through symlinks, atomically, keeping permissions; installing twice is byte-identical. **Remove** restores the backup byte for byte if the file is still what Notched wrote (hash match), else removes just its entries.
- **Sessions** (`ClaudeSessionsReducer`): `UserPromptSubmit` → "Claude is working…"; a permission request alerts the island with Allow / Deny (and Always Allow when Claude Code offered a rule, Deny and Stop, Answer in Terminal); `Stop` shows a banner only after ≥ 10 s of work; a hung-up hook removes its card; sessions forgotten after an hour of silence; a session waiting for an approval is never forgotten.
- **Privacy:** the prompt text is never read; displayed commands go through `SecretRedactor` (known token formats, bearer/authorization values, `--password`-style flags, `SECRET=`-style assignments, URL credentials, private keys, long mixed runs) and are truncated to 160 characters. The real request is untouched.

## To verify on the Mac (can't be known from the docs)

1. Does Claude Code show its own terminal prompt while a `PermissionRequest` hook is still running, or only after it returns? If only after, a user at the terminal waits up to the approval wait; "Answer in Terminal" and a shorter wait cover it.
2. When the terminal answers first, does Claude Code kill the hook (so the card disappears)?
3. Hooks are held back until the folder is trusted (documented).
4. Run `claude` then `/doctor` after installing: make sure it accepts the `args: []` key and the `StopFailure` event. If an older Claude Code rejects either, drop it from `ClaudeSettingsMerger`.
