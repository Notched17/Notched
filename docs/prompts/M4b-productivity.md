We're continuing Notched. M1–M4a are done ✅ (confirm in `docs/ROADMAP.md`; if M4a isn't merged into `main`, stop and tell me). This is **M4b**: the productivity modules (clipboard, calendar + join, reminders, weather, colour picker, terminal) and the **layout editor**. These are mostly public-API and UI work, so most of the session is polish.

## Model guide (for me, not for you)
Plan mode: Opus high. Everything else: Sonnet. Settings panes, docs, ROADMAP updates, running tests: Haiku via `build-runner`/`Explore`. Use Opus again only for the final fresh review.

## Read first
1. `CLAUDE.md` (binding) and `docs/ROADMAP.md` M4 rows **#45, #48 (+#49), #50, #51, #55, #64, #71**.
2. The M4a tab-host (expanded tabs) code and module template; the reducer convention; `docs/ISLAND-BEHAVIOR.md` §4 (regions).
3. The Liquid Glass and HIG skills; Apple's own Calendar/Reminders/Weather as visual references.

## Step 0: Plan (plan mode)
Plan, wait for approval. Include per-module: data source, permission and when requested (lazily, when the module is turned on), tab layout, compact/minimal presence, reducer states and tests, empty/denied/offline states, and **questions for me** (e.g. weather location method, clipboard retention).

## Build order (build, test, install, screenshot, critique, commit after each)
Every module: its own folder, settings section, on/off toggle, zero cost when off, a tested reducer for anything with a lifecycle, and sensible **denied-permission** UI.

1. **#55 Colour picker.** Button in the Home tools row → `NSColorSampler` (no Screen Recording permission needed). Swatch + HEX/RGB/HSL with copy buttons and a recent-colours row (persisted, capped).
2. **#45 Clipboard history.** A tab with search, pin, type icons (text/image/file/URL), source-app icon, click to copy back, ⌘⇧V hotkey (use a public hotkey API, no event tap).
   - Poll `NSPasteboard.changeCount` through `RefreshScheduler` (~0.5 s only while the module is on). Skip `org.nspasteboard.ConcealedType` and `TransientType`; excluded-apps list; history length; clear on quit option.
   - Store in a small SQLite/SwiftData file in Application Support, **never** log clipboard contents, cap image sizes. Explain macOS's pasteboard-privacy prompt in onboarding. Never auto-paste with `CGEvent.post` by default.
3. **#48 + #49 Calendar and one-click Join.** EventKit full access; compact countdown to the next event within 15 minutes (configurable), as a `live` activity with an alert expansion 1 min before start; agenda tab for today and tomorrow with calendar colours; detect Zoom/Meet/Teams/Webex URLs in location, URL and notes for a Join button. Listen for `EKEventStoreChanged` (no polling). Hide declined/cancelled events; all-day events don't trigger countdowns.
4. **#50 Reminders.** EventKit reminders: today + overdue list in a tab, checkboxes complete them (with undo for 5 s), due-soon banner optional.
5. **#51 Weather.** Open-Meteo (free, no key). Location: approximate CoreLocation **or** a manual city (default to manual if Location is denied). Compact temperature + condition symbol (optional), expanded current + hourly + high/low. Refresh every 30 min only while the module is on; cache last result; show "offline" state; units follow the system. Weather is passive class: never steals the island from a live activity.
6. **#64 Terminal.** An expanded "Terminal" tab hosting a real shell with **SwiftTerm** (MIT, `LocalProcessTerminalView`). Typing needs key status: allow the panel to become key only while the terminal tab is focused and relinquish on collapse; Esc collapses (Ctrl+C etc. pass to the shell). Shell from `$SHELL`, login env, working directory = home. Hover-expansion must not collapse while typing; add a "Pin open" toggle. Audit the key-status handling against CLAUDE.md panel rules (no focus theft from other apps when collapsed). Attribute SwiftTerm in `THIRD_PARTY_NOTICES.md`.
7. **#71 Layout editor.** Settings pane with drag-and-drop to choose which modules appear in the compact slots, the order of expanded tabs, and per-module "show in compact" toggles. Persist in `SettingsStore`; feeds `ActivityCoordinator` priority (reuse M3b's priority settings; don't duplicate). Live preview of the island in the pane. Reset-to-default button.

## Verify
- Screenshots in `docs/screenshots/m4b/` for every module (tab, compact where it exists, denied state), notch and pill, plus the layout editor and the full tab bar with every tab enabled (it must still fit).
- Real use: copy 100 items (including a password manager entry: must be skipped), join a test event, complete a reminder, type in the terminal for a few minutes including `vim`, `top` and resizing, deny each permission, offline weather.
- Robustness: sleep/wake, enable/disable all modules repeatedly (no leaks), terminal process cleanup on quit and on tab close (no orphan shells; check `ps`).
- Performance with everything on: idle < 0.5% CPU, memory < 150 MB; report per-module cost with `scripts/cpu.sh`. Clipboard polling must show ~0 when idle.
- Update ROADMAP, ADRs (clipboard privacy, terminal key handling, weather location), `THIRD_PARTY_NOTICES.md`; run a fresh-reviewer pass on the branch and fix critical/important findings.
- Final report: built, screenshots, numbers, what works on macOS 27.2, decisions, things for me to try, and suggestions for M6.

If a spec is impossible or wrong in practice, stop and tell me. Don't merge or push without asking.
