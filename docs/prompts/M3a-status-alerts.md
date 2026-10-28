We're continuing Notched. M1, M1.5 and M2 are done ✅. This session is **M3a: the cheap, public-API status modules**, plus the foundation work that M2's review asked for before more modules arrive. M3b (call, screen recording, downloads, camera/mic, Focus, user-adjustable priority) is a separate session, because those are heuristic or private-API and need their own care.

## Housekeeping first (before Step 0)
1. Confirm `m2-media` is merged into `main` (I'm merging it myself before this session: if you're still on `m2-media`, stop and tell me). Create `m3a-status` from `main`.
2. Read `docs/ROADMAP.md` M2 status. Don't change any M2 behaviour except where Step 1 below says so.

## Read first
1. `CLAUDE.md` (binding, including the Token economy section: use the `Explore` and `build-runner` subagents).
2. `docs/ROADMAP.md`, the **M3** section, rows #25, #26, #27, #29, #38, #37.
3. `docs/ISLAND-BEHAVIOR.md`, especially §1 (transient banners vs live activities), §2 (lifecycle), §4 (regions).
4. ADR-0006 (activity model), ADR-0007 (bubbles) and ADR-0008 (the Now Playing reducer and backend pattern).
5. `Sources/Modules/Media/` and `Sources/Services/Audio/`: the reference implementation. New modules must follow the same shape, and reuse the CoreAudio device code rather than duplicating it.
6. The M2 final report in `docs/superpowers/` (decisions 1–14 and the deferred review findings).

## Tools
- **superpowers:** brainstorm, plan, TDD, systematic debugging, verify. Save spec and plan to `docs/superpowers/`.
- **liquid-glass + hig-\*** for all UI. The iPhone Dynamic Island banners (charging, AirPods connect, silent mode) are the visual reference.
- **Xcode MCP** (fallback `xcodebuild`) and `screencapture`; look at every screenshot and critique it. Send builds and test runs to `build-runner`.

## Step 0: Plan (plan mode)
Propose a plan and wait for my approval. Cover:
- **Step 1 foundations** (below), with the exact types.
- **A shared `BannerSource` pattern** for transient banners (charging, Bluetooth, Wi-Fi, Caps Lock): how a module emits a banner through the coordinator without taking a minimal slot, how repeated events are de-duplicated and rate-limited (e.g. flapping Wi-Fi), and how banners interact with an alert expansion in progress.
- **Per-module tested pure reducers** (event + state → new state + effects). List the reducer states and the unit tests for each module.
- **Permissions:** which of these modules need one (Bluetooth for #27, maybe Location for the Wi-Fi name in #29), how each is requested lazily (only when the user turns the feature on), and what the module shows when it's denied.
- **Questions for me.**

## Step 1: Foundations (build, test, commit separately)
1. **Module start-up refactor.** Move module start/stop out of the observation code in `AppEnvironment.applySettings` into a proper `ModuleHost` that owns lifecycle (enable, disable, crash-loop protection). Behaviour must not change; existing tests must stay green. Add tests for enable/disable ordering.
2. **Reducer convention.** Document in `CLAUDE.md` (module contract) that every live module has a pure, unit-tested reducer for its lifecycle, as Now Playing does. Add a short template to `docs/`.
3. **Promote tools.** Move the precise CPU-measurement script and the test audio player from the scratchpad into `scripts/` as proper, documented tools (`scripts/cpu.sh`, `scripts/test-player`), and update `scripts/perf.sh` to use them. Make sure `build-runner` knows about them.
4. **M2 cleanup items** from the deferred review list that touch code you'll be editing anyway (output switching off the main thread, the 2-per-second lyric ticker). Skip the rest.

## Step 2: Modules (build, test, install, screenshot, commit after each)
Each module is its own folder under `Sources/Modules/`, has its own settings pane section and an on/off toggle (default on unless noted), and costs nothing when off.

1. **#26 Battery (and charging).**
   - Transient banners: charging started/stopped, full, low (20% and 10%, configurable).
   - A `live` activity only while charging below the user's "show while charging" threshold (setting; default off, banners only).
   - Expanded view: percentage ring, time remaining, power source, charger wattage if available.
   - Hidden entirely on Macs with no battery.
   - IOKit `IOPSNotificationCreateRunLoopSource`; no polling.
2. **#27 Bluetooth and output toasts.**
   - "AirPods Pro connected" banner with a device-type SF Symbol (reuse the symbol mapping from M2's output switcher).
   - Audio devices via the CoreAudio listeners you already have; non-audio devices (keyboard, mouse, trackpad) via IOBluetooth only if it needs no extra permission, otherwise skip them and say so.
   - Request the Bluetooth permission lazily.
3. **#29 Network.**
   - `NWPathMonitor`: banners for Wi-Fi ↔ Ethernet ↔ offline, with debounce so brief flaps don't spam.
   - Wi-Fi name (SSID) is **optional** and off by default because it needs Location permission. Without it the banner says "Wi-Fi connected".
4. **#25 Caps Lock.**
   - Banner on toggle with a lock glyph filled/unfilled.
   - Use a global `NSEvent` monitor for `.flagsChanged`. Check whether it works with no Accessibility permission on macOS 27.2; if it needs one, make the module optional and explain why in Settings. Never request Input Monitoring.
5. **#38 Keep-awake.**
   - A toggle in the expanded Home view and in the menu-bar menu; a coffee-cup compact indicator while active, with a countdown in the minimal bubble.
   - Presets: 30 min, 1 h, 2 h, indefinitely.
   - `IOPMAssertionCreateWithName` (`PreventUserIdleDisplaySleep`). Release it on quit, on crash recovery, and when the timer ends. Test that it never leaks.
   - Class `live`; hideable.
6. **#37 Timers and stopwatch.**
   - Multiple countdown timers plus a stopwatch, as `live` activities. Compact: ring + remaining time. Minimal bubble: the countdown. Expanded: presets (1, 5, 10, 25 min), custom entry, pause, add 1 min, cancel.
   - On completion: alert expansion with a sound (system sound, setting for which one), then the activity ends and appears in Recent.
   - `Date`-based (end date), no polling per second. Survives sleep/wake and app relaunch (persist active timers).
   - Start from the expanded view, the menu-bar menu and a `notched://timer?minutes=10&label=Tea` URL.
   - The progress ring animates like the M2 visualiser: Core Animation in the render server, not a SwiftUI per-frame timeline. Stop it when hidden or covered.
   - Replace the Scenario Lab "Timer" with the real module, but keep the Lab as a DEBUG tool for the other demos.

## Verify
- Screenshots in `docs/screenshots/m3a/`: each banner (notch screen and non-notch pill), battery expanded, a timer compact + a timer bubble beside Now Playing, expanded Timers, keep-awake compact, three-activity layout (music + timer + keep-awake), and each module's settings pane section.
- Critique each against the iPhone island and fix anything not Apple-quality.
- Robustness:
  - sleep and wake with timers and keep-awake running
  - quit and relaunch with a running timer
  - Wi-Fi off/on repeatedly (no banner spam)
  - connect and disconnect AirPods
  - deny the Bluetooth permission
  - unplug and replug the charger
  - enable and disable every module repeatedly (no leaked assertions, listeners or timers)
- Performance with all M3a modules on:
  - idle < 0.5% CPU
  - Now Playing compact < 1.5%
  - a timer running compact < 1%
  - memory < 150 MB
  - report measured numbers using `scripts/cpu.sh`
- Update `docs/ROADMAP.md` (mark rows ✅ with notes and measured numbers, and move "Mirror the Clock app timers" to Later), add ADRs for the banner pipeline and for any permission decisions, and update `THIRD_PARTY_NOTICES.md` if you used any third-party code.
- Finish with a short report: what was built, screenshots, performance numbers, what works and doesn't on macOS 27.2, decisions you made, questions for me, suggestions for M3b.

If a spec turns out impossible or wrong in practice, stop and tell me rather than quietly doing something different.
