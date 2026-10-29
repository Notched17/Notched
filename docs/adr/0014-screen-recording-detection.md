# ADR-0014: Screen recording detection works; the module is deferred

- Status: accepted (M3b spike S2)
- Date: 2026-10-28
- Mac: Mac16,13, macOS 27.2, Debug build signed with Apple Development, run from `~/Applications`. Notched had **no** Screen Recording permission.

## Context

The M3b brief asks for a red recording indicator with elapsed time and a Stop button, as a non-hideable `system` activity. No public API reports "the screen is being recorded". The plan (`docs/superpowers/specs/2026-10-28-m3b-system-design.md`, S2) required a spike before any code.

## Findings (DEBUG probe inside the installed app)

1. **The private SkyLight route works.**
   - **Calls:** `SLSRegisterNotifyProc(proc, type, userData)` with notify types **1502** (a screen watcher appeared) and **1503** (it went away). Both are delivered on the main thread with no data. `SLSIsScreenWatcherPresent()` agrees with them.
   - **Exports:** `SLSRegisterNotifyProc`, `SLSRemoveNotifyProc` and `SLSIsScreenWatcherPresent` are all present. The old `CGS…` aliases are **gone** on 27.2. The type numbers come from community code (Atoll, DynamicNotch), read for ideas only.
   - **⌘⇧5 "Record Entire Screen":** 1502 fired at 20:35:30.56, the same second in the saved file's name, and 1503 fired when it stopped.
   - **`screencapture -v -V 4`:** 1502, then 1503 exactly 4.0 s later.
   - **Still screenshots** (`screencapture -x`) and ⌘⇧5 sessions that were cancelled without recording **never** fired 1502. A debounce is still wise, but screenshots don't cause false positives.
   - **No permission** is needed. No prompt appeared.
   - Type 1507 fires now and then, and 1508 when windows come and go; both are unrelated.
2. **Public signals only help a little.**
   - `com.apple.screencaptureui` launches as soon as ⌘⇧5 opens and stays running ~20 s after a recording, so on its own it can't tell recording apart from just showing the toolbar.
   - Without Screen Recording permission, the window list gives owner names (`screencapture` layer 1498, `Screenshot` layer 24/1499) but no titles.
3. **Stop.**
   - **SIGINT** to `screencapture -v` (the command line) stops it and saves a valid movie (2.9 s, playable).
   - SIGINT to the `screencapture` process behind a **⌘⇧5** recording is delivered (`kill` returned 0) but **ignored**. The recording carried on until Charlie used the menu-bar Stop button.
   - **⌘⌃Esc** sent from Notched wasn't tried; it would need Accessibility.
   - **SIGTERM to `screencaptureui` was deliberately never tried**: it would lose the recording.
4. Not tried: QuickTime, third-party ScreenCaptureKit recorders, and FaceTime/Zoom screen sharing. ScreenCaptureKit clients probably raise the same watcher signal, so a shipped module would need a list of sharing apps to ignore.

## Decision

- **Charlie deferred the Screen recording module** ("I don't think I will be screen recording anything any time soon"). No module ships in M3b, and the probe is removed.
- When it returns, the route is settled:
  - a `Services/Private/SkyLightScreenWatcher.swift` wrapper, found by `dlsym` on the three `SLS…` symbols, with the feature hidden if any is missing;
  - registered in `start()` and removed with `SLSRemoveNotifyProc` in `stop()`;
  - a 1 s debounce; elapsed time measured from 1502;
  - posted with `alertsWhenStarted: false`, so it doesn't expand into the recording.
  
  Stop is open:
  - try ⌘⌃Esc sent as a `CGEvent` (Accessibility, as a sub-toggle);
  - keep SIGINT only for `screencapture -v`;
  - otherwise ship without a Stop button.
- The `alertsWhenStarted` coordinator flag is no longer needed in M3b. A0 leaves it out.
