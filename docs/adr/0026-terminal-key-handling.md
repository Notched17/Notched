# ADR-0026: The Terminal tab: keyboard focus, Esc and the shell's life

- Status: accepted for M4b Step 6 (#64); **written on Linux, not yet compiled or run**
- Date: 2026-10-31
- Spec: `docs/superpowers/specs/2026-10-31-m4b-productivity-design.md` §4.6, §8 (answer 5)
- Builds on: ADR-0020 (tabs), the panel rules in CLAUDE.md ("no focus theft from other apps when collapsed")

## The rules (all pure and tested in `IslandKeyboardPolicy`)

1. **The island never takes keyboard focus on hover**, as before. Focus comes only after a click: on the tab bar or elsewhere in the island (the hosting view's `onMouseDown`), or inside the terminal (below). It is handed back to the user's app on every collapse (`giveBackKeyFocus`, unchanged).
2. **Esc goes to the shell** (vim needs it); **⌘Esc collapses**. For every other tab Esc still collapses. The panel's `contentOwnsKeyboard` flag, kept in step with the selected tab's `capturesKeyboard`, switches this. A key the terminal view handles never reaches the panel, so the panel's Esc path only runs for keys the content ignored.
3. **Ctrl-C, Ctrl-D, Tab and the plain arrow keys are the shell's.** `ExpandedTabs.command` drops ← → paging for a capturing tab; ⌘1–⌘5 and ⌃Tab still switch tabs.
4. **⌘C, ⌘V, ⌘A are forwarded to the terminal** with `NSApp.sendAction(copy:/paste:/selectAll:, to: nil)`, because an agent app has no Edit menu to route them.
5. **The island stays open while the shell has keyboard focus**, or while the user has pressed *Keep Open* (the pin). The pointer leaving is ignored in those cases (`keyboardTabHoldsIslandOpen`). When focus is lost to another app (`didResignKey`) with the pointer already away and no pin, the island closes. The plan's "3 s after the last keystroke" grace was dropped: key focus is the better signal and needs no keystroke tracking.
6. **A click inside the terminal asks for focus explicitly**, because the terminal is a subview that takes the click before the hosting view sees it. `TerminalContainerView.hitTest` notices the left-mouse-down, calls `IslandCommands.requestKeyFocus` (which, like everything else, only acts on an expanded island on the pointer's display) and makes the terminal first responder. This is a pragmatic use of `hitTest`; the alternative, an event monitor, would hold a global hook.
7. **Alerts win.** During an alert the selected tab is not shown (ADR-0020), so none of the above applies until it ends.

## The shell

- Started **the first time the tab is shown**, not when the module is switched on, so enabling Terminal costs nothing. A login shell (`$SHELL`, validated; zsh if not usable) started through `/bin/sh -c 'cd "$1"; exec "$0" -l' <shell> <home>` so the working directory is the home folder without changing Notched's own, and nothing is spliced into the script (tested with hostile paths).
- Owned by the **module**, not the tab: it keeps running while the island is collapsed and the tab content is rebuilt (the SwiftTerm view is re-hosted).
- Ended when: Terminal is turned off, Notched quits (`willTerminate`, also via `stop()`), the user presses End Session, or the shell exits. `TerminalProcessKiller` sends SIGHUP to the shell's process group (a forkpty child leads its own), waits up to 0.4 s, then SIGKILL; it never signals pid 0 or 1.
- **Crash-loop guard:** two shells in a row that exit within a second stop showing-the-tab from restarting one; New Session does. Each start has a generation so a late exit report can't end the next shell.
- The tab asks for a taller island (content 250 pt, limit 310 pt) through `IslandTab.maxContentHeight`; the panel is sized for the tallest tab when the tab is added (ADR-0002: never resized during interaction), and other tabs keep the 160 pt limit.

## Security note

The shell has the user's own permissions, like Terminal.app, and the tab is off by default. Nothing the shell prints or the user types is logged. No Full Disk Access or other permission is requested; macOS applies its usual privacy prompts to whatever the user runs.

## Open until checked on the Mac (this is the riskiest step)

- **SwiftTerm's exact API** (package held to the 1.2 line): `LocalProcessTerminalView`, `startProcess(executable:args:environment:execName:)`, `process.shellPid`, `nativeBackgroundColor`, and the four delegate methods were written from memory.
- Whether a click really gives the terminal first responder and typing works at once; whether Esc reaches the shell and `cancelOperation`/⌘. don't interfere; whether ⌘C/⌘V reach SwiftTerm's `copy(_:)`/`paste(_:)`.
- That closing the island hands focus back to the previous app without a flash, and that clicking another app closes a focused Terminal island.
- That the panel growing to 310 pt of content when the tab is added doesn't disturb the compact island.
- `vim`, `top`, resizing (the pty must follow the view), and `ps` after quitting and after switching the module off: no shell may be left.
