# M4a: what to do on the Mac

M4a was written without Xcode (see the ROADMAP status). This list is how to finish it. Do it in order; stop at the first failure and send me the output.

## 1. Build and test

1. `xcodegen generate` (a new target `notched-hook` and new folders were added).
2. Build: `xcodebuild -project Notched.xcodeproj -scheme Notched -configuration Debug -derivedDataPath build build`. **Expect compile errors** in the files that couldn't be compiled where I wrote them: `Sources/Services/LocalAPI/LocalAPIServer.swift`, `Sources/Modules/ActivityAPI/*Presentation.swift`/`*Pane.swift`, `Sources/Core/Activities/ApprovalCard.swift`, `Sources/Modules/ClaudeCode/ClaudePresentation.swift`, `ClaudeAITab.swift`, `ClaudeCodeModule.swift`, `ClaudeCodeSettingsPane.swift`, `ClaudeUsageService.swift` (the FSEvents class). Paste me the errors.
3. Run the tests. `APIModuleTests` and the existing `SymbolNameTests` are the new Mac-only ones; the other new suites ran 148 passing tests on Linux.
4. Confirm `Notched.app/Contents/MacOS/notched-hook` exists and `notched-hook --version` prints `1`.

## 2. Activity API: turn it on, then try to break it

5. Install to `~/Applications/Notched.app`, launch, **Settings ▸ Modules ▸ Activity API**: turn it on. The pane should say "Listening on 127.0.0.1:<port>".
6. `lsof -nP -iTCP -sTCP:LISTEN | grep Notched` must show `127.0.0.1:<port>` (the same port Settings shows), **not** `*:<port>`, and the pane must go from "Starting…" to "Listening" without flicker or "Port in use". (If it shows `*`, tell me: the listener binding needs a fix, ADR-0021.)
7. **New Client…** (name `test`, all scopes). Copy the token. `export NOTCHED_PORT=… NOTCHED_TOKEN=…`
8. Post a progress activity (the curl in `docs/ACTIVITY-API.md`). Check it on the notch and the pill, update the progress, `DELETE` it, post a countdown, an `alert: true` one, and a banner.
9. Refusals; each must give the status shown:
   - no token → 401 `missing_token`: `curl -i http://127.0.0.1:$NOTCHED_PORT/v1/activities`
   - wrong token → 401 `invalid_token`: add `-H "Authorization: Bearer ntch_wrong"`
   - from a web page → 403 `browser_forbidden`: add `-H "Origin: https://evil.example"`; also open DevTools on any site and run `fetch("http://127.0.0.1:PORT/v1/activities",{headers:{Authorization:"Bearer x"}})` (it must fail)
   - wrong Host → 421: `curl -H "Host: evil.example" …`
   - oversized body → 413: `head -c 20000 /dev/zero | tr '\0' a | curl -X PUT … --data-binary @-`
   - 25 quick requests → some 429
   - 6th activity from one client → 409
   - `OPTIONS` → 405 with no `Access-Control-*` header
10. **Revoke** the client: its activities leave the island at once and its token gives 401.
11. Turn the module off: `lsof` shows no listener, and `~/Library/Application Support/Notched/api.json` is gone.
12. `notched://banner?title=Hi`: nothing until "Allow banners from notched:// links" is on; then a banner saying "via link".

## 3. Claude Code hooks

13. **Settings ▸ Modules ▸ Claude Code**: turn the module on. Press **Install Hooks…**: the diff sheet should show only added lines under `"hooks"`. Install.
14. Check `~/.claude/settings.json` (your keys and order unchanged), a `settings.json.notched-backup-…` beside it, `~/.local/bin/notched-hook`, and `~/Library/Application Support/Notched/claude-hook.token` (mode `-rw-------`).
15. Run `claude` once in the scratch folder below and then `/doctor`: it must not complain about the new hooks (`args`, `StopFailure`). If it does, tell me which key.
15b. In a **scratch folder** (`mkdir /tmp/scratch && cd /tmp/scratch && git init`), run `claude` and trust it. Ask it to do something slow so you see **"Claude is working…"** with the folder name, then something that needs permission (`run date in bash`). The island should expand with the command and **Deny / Allow**.
16. Answer **Allow** on the island: Claude Code continues. Repeat with **Deny**, **Deny and Stop Claude**, **Answer in Terminal** (Claude Code's own prompt must appear), and **Always Allow …** (check the rule it adds).
17. **Open question A:** while the island card is up, does Claude Code *also* show its terminal prompt, or wait? Tell me which. **Open question B:** answer in the terminal while the card is up: does the card disappear?
18. Let a turn run over 10 s: a "Claude finished" banner. A quick turn: none.
19. **Kill Notched during an approval** (`killall Notched` while the card is up): Claude Code must fall back to its own prompt within a second or two, and carry on normally. Also try with Notched not running at all, then with the module off.
20. Leave an approval unanswered for the wait (90 s): Claude Code falls back to its prompt, and the card goes away.
21. Press **Install Hooks…** again: it should say already installed. **Remove Hooks…** with an untouched file: the sheet says "Restore the original settings", and `diff` against the backup shows nothing. Install, edit settings.json yourself (change `model`), then Remove: only the Notched entries go.
22. Put invalid JSON in a copy of settings.json (point nothing at it; edit the real one and undo): Install must refuse and not touch the file.

## 4. Claude Code usage (AI tab)

23. Hover the island to expand it; there should be an **AI** tab. Open it: Today / This week with ≈ cost, 7-day bars, sessions.
24. Compare "Today" with `npx ccusage daily` (it should be close; ccusage prices differently). If the numbers are 2–3× too high, dedupe is failing: send me one log line.
25. Run Claude Code while the tab is open: numbers update within a few seconds.
26. Point at your biggest log: `ls -lS ~/.claude/projects/*/*.jsonl | head -3`. Open the tab and time it; the first read of a 100 MB log should finish in well under a minute and not stall the island.

## 5. Robustness and numbers

27. Sleep/wake the Mac with an approval card up and with the API on; it should still answer.
28. Idle CPU with the Activity API on and no clients, and Claude Code on with the tab closed: `scripts/cpu.sh` (budget < 0.5%, memory < 150 MB). Then with the tab open during a Claude Code run.
29. Screenshots into `docs/screenshots/m4a/`: tab bar, AI tab, Claude working, approval card, finished banner, Activity API settings, Claude Code settings with the diff sheet; notch and pill for each. Send me any that look wrong.
30. Check Keychain Access for `me.rkck.Notched.api` items (hashes, one per client). If macOS asks for access after a rebuild, that's the signature changing; use the stable Apple Development identity.

## What I'd look at first if something is off

- Nothing listens: `LocalAPIServer.start` (the `requiredLocalEndpoint` + `on:` combination is the least certain line).
- Hooks run but nothing shows: `NOTCHED_HOOK_DEBUG=1` before `claude`, and `log stream --predicate 'subsystem BEGINSWITH "me.rkck.Notched"'`.
- Approval card never answers: `ClaudeCodeModule.handleHook` and `ApprovalWaiter`.
