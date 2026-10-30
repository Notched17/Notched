# Roadmap

Feature numbers match the master checklist in `docs/research/notch-app-research.md`. Build the milestones in order. Each one should end with a working, installed app, passing tests, a performance check (see the budget in CLAUDE.md) and a git commit.

**Status key:** ⬜ not started · 🟨 in progress · ✅ done · ⏸ parked

---

## M1: Shell and foundations

Goal: a beautiful, stable island that appears in the right place on every display, morphs smoothly, and has the plumbing every later feature needs.

| # | Feature | Spec and acceptance criteria | Approach |
|---|---|---|---|
| 1 | ✅ Notch overlay, compact ↔ expanded | Hovering (with a short configurable delay) or clicking expands it, and it collapses when the pointer leaves. Expand/collapse is one continuous spring morph. Idle shows the bare notch (black, invisible against the hardware notch) or the pill on non-notch screens. | Borderless, non-activating, transparent `NSPanel` subclass: `canBecomeKey`/`canBecomeMain` false by default, level `.mainMenu + 3` (match boring.notch), and collectionBehavior `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Position it from `screen.frame` (not `visibleFrame`), top centre. `NotchGeometry`: a notch exists when `safeAreaInsets.top > 0`; width = `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width` (plus a small fudge); height = `safeAreaInsets.top`. Without a notch, use the menu-bar height for a pill. Rebuild on `NSApplication.didChangeScreenParametersNotification`. Study DynamicNotchKit (MIT) and boring.notch (GPL) for the window code. |
| — | ✅ Multi-display basics | One island per screen; the user chooses "main display only", "all displays" or a specific display. | One `IslandController` per `NSScreen`, keyed by display UUID. |
| 5 | ✅ Auto-hide in fullscreen | Hide when the frontmost app on that screen is fullscreen (games, video). Optional setting: keep showing during fullscreen media (✅ built in M2). | Watch active-space changes (`NSWorkspace.activeSpaceDidChangeNotification`) plus frontmost-app window bounds versus screen frame. Test with Safari video fullscreen and a fullscreen game. |
| 6 | ✅ Hide from screenshots/recordings (toggle) | Setting off by default. When on, the island doesn't appear in screenshots or screen sharing. | `panel.sharingType = .none`. Note in the UI that some capture tools may still see it. |
| 7 | ✅ Click-through around the island | Menu-bar items and app menus beside the notch stay clickable. Only the visible island shape takes clicks. | Keep the panel the size of the current island shape and resize it as the island morphs, or toggle `ignoresMouseEvents` with a global mouse-moved monitor and hit-testing. Hover must still work. Test the File/Edit menus of a wide-menu app. |
| 70 | ✅ Per-feature toggles | Modules pane in Settings: every module has a toggle, a description and its required permissions. | `ModuleRegistry` + `SettingsStore`. Disabled modules cost zero CPU. |
| 72 | ✅ Size, position, animation tuning | Sliders: island width offset, expanded size, hover delay, animation style (Snappy / Smooth / Bouncy) with a live preview. | Spring tokens in `DesignSystem`. |
| 73 | ✅ Materials and themes | Theme per display type: "Notch black" (default on notch), "Liquid Glass" (default on pill), "Tinted glass" (accent tint). Honour Reduce Transparency. | `.glassEffect`, `GlassEffectContainer`. See the design section of CLAUDE.md. |
| 77 | ✅ Menu-bar agent, launch at login, onboarding | `LSUIElement` app. Status item menu: Settings…, Pause island, About, Quit. "Launch at login" uses `SMAppService.mainApp`. The first-run onboarding is a short, beautiful 3–4 step window: welcome → choose modules → permissions (only for chosen modules) → done. | `PermissionCenter` shows the live status of each TCC permission, with a button that opens the right System Settings pane. |
| — | ✅ Infrastructure | `ActivityCoordinator` (with unit tests), `RefreshScheduler`, `PermissionCenter`, `os.Logger` subsystems, GPL LICENSE, `THIRD_PARTY_NOTICES.md`, `.gitignore`, `README.md`. | — |

**Status:** ✅ M1 complete (27 Oct 2026). See ADRs 0001–0005 for the decisions.

**M1 demo module:** a tiny built-in "Hello" activity, triggered from a debug menu item, that proves activities flow through the coordinator into the compact and expanded views. Remove it or hide it behind a DEBUG flag later.

---

## M1.5: Island behaviour (iPhone parity) and rename

Goal: the island *behaves* like the iPhone Dynamic Island before media is built on it. Spec: `docs/ISLAND-BEHAVIOR.md`. Decisions: ADR-0006 (live activity model) and ADR-0007 (minimal bubbles).

| # | Feature | Spec and acceptance criteria | Approach |
|---|---|---|---|
| — | ✅ Rename to Notched | Product, bundle ID `me.rkck.Notched`, URL scheme `notched`, logs, scripts, docs. Old install removed, settings migrated, TCC reset. | One `chore` commit. |
| 8 | ✅ Live activity model | One primary activity owns both compact sides. Kind → relevance → start order. Up to 3 on the island (bubbles), the rest listed. Sticky swap, hide (non-hideable system activities), stale, ended → Recent. | `LiveActivity`, `ActivityPresentation` regions, `ActivityCoordinator` with scenario tests. |
| 8 | ✅ Alerts and banners | Alerting updates expand the island for a few seconds and return. They queue, and wait while the pointer is on the island. Transient banners (wide compact, 2 s) for system events. | Coordinator deadlines + `HoverStateMachine` `.alerting`. |
| 8 | ✅ Presentation template | Expanded regions laid out with Apple's algorithm. The island owns animation (≤ 2 s, numeric text, blur-replace). Height follows content. | `ExpandedRegionsLayout`, `IslandRegionHost`. |
| 8 | ✅ Minimal bubbles + side by side | Detached black circles/ovals 6 pt from the island that bud off and merge back. Width budget notch + 2 × 90 pt. Click-through between them. Setting: Bubbles / Side by side (iPhone 18 Pro). Keyline in Dark Mode. | Drawn in the island panel; one sensor window per region (ADR-0007). `CompactLayout` tested. |
| 8 | ✅ Interaction | Hover expands the hovered activity. Click opens it ("Click to expand" setting). Click a bubble → primary. Two-finger swipe cycles / hides. Right-click → Hide. Expanded paging + Home activity list (Live, Hidden, Recent). Esc. | `SwipeRecognizer` tested; context menu; non-activating key focus after a click. |
| — | ✅ Scenario Lab (DEBUG) | Music, Timer, Call, Claude Code, Download demos, a Charging banner, a Timer Done alert and a scripted full demo, through the real coordinator. | Debug ▸ Scenario Lab, `notched://debug/lab?…`. |

---

**Status:** ✅ M1.5 complete (27 Oct 2026). Idle CPU 0.04%, 0.81% with a ticking timer, 18–19 MB footprint. Screenshots in `docs/screenshots/m1.5/`. Left for M2: the music visualiser must animate in the render server (a SwiftUI `TimelineView` level meter costs ~7% CPU).

---

## M2: Media

Goal: Apple-quality Now Playing in the island for any app, as a `.media` live activity. Spec: `docs/superpowers/specs/2026-10-28-m2-media-design.md`. Decisions: ADR-0008 (backends), ADR-0009 (lyrics privacy), ADR-0010 (visualiser).

| # | Feature | Spec | Approach and risk |
|---|---|---|---|
| 9 | ✅ Now Playing | Compact: artwork (leading) and a live visualiser (trailing). Minimal: bars while playing, an artwork circle while paused. Expanded: artwork, title, artist with the source app's icon, scrubber, transport controls, output device, optional lyric line. Clicking the island or the artwork opens the source app. Paused media dims after 2 min and leaves after 10 (both settings); "Briefly expand on track change" (off). | `MediaModule` → one `LiveActivity` (`media.nowPlaying`, kind `.media`). The artwork accent tints the bars and keyline (`ArtworkColor`, tested). **Not built:** media swipe gestures, because horizontal swipes already cycle activities (ADR-0006). |
| 10 | ✅ Any-app source detection | Works for any app in Control Center's Now Playing: verified with Chrome/YouTube and two test players on macOS 27.2. Falls back to Music and Spotify. | **ungive/mediaremote-adapter 0.7.7**, vendored and built by XcodeGen (`Vendor/mediaremote-adapter/NOTCHED.md`), one `stream --micros` process. Fallback: Music/Spotify notifications + AppleScript. Health: fatal exit → fallback (verified: switches in ~25 ms); a cross-check runs the adapter's self-test when a player says it's playing but the adapter sees nothing. ADR-0008. |
| 11 | ✅ Seek bar and ±15 s skip | Apple Music-style scrubber: thickens on hover, drag previews the time, seeks on release; `−remaining` time. ±15 s for sources that support it or content ≥ 20 min. Live streams show LIVE. | Elapsed time is interpolated from timestamp and rate (`PlaybackTimeline`, tested), redrawn twice a second only while expanded and playing. |
| 12 | ✅ Animated visualiser | 4–5 rounded bars, phase-shifted sines + seeded value noise, eased in and out, tinted by the artwork. Styles: Animated / Still / Off. | Core Animation keyframe loops in the render server; removed when hidden, covered, paused or with Reduce Motion. **Measured:** 0.017% CPU playing (compact), 0.317% expanded, 0.000% idle (ADR-0010). |
| 13 | ✅ Synced lyrics (notch part) | Current line under the expanded controls; optional ticker beside the notch (fits ~10 characters in the 64 pt region). Lock-screen lyrics stay in M6. | LRCLIB `/api/get` by title, artist, album and duration; LRC parser and line lookup tested; hashed disk cache (not-found cached for 7 days). **No network unless lyrics are on** (ADR-0009; verified with `lsof`). |
| 15 | 🟨 Like / favourite the song | Heart for Apple Music: toggles the track's `favorited` (`loved` is gone on macOS 27.2). Reads the state only if Automation is already allowed; the first tap asks. | **Spotify not built:** its AppleScript `starred` is read-only, so liking needs the Web API (OAuth PKCE, Charlie's developer app). Waiting for Charlie's decision. |
| 16 | ✅ Output device switcher | Current output's symbol (AirPods, Beats, headphones, laptop, display, AirPlay…) at the end of the controls row, like AirPlay on iPhone; a native menu lists every output with a check. | CoreAudio device list, default output and data source, kept current by property listeners while the module runs. Symbol mapping tested. |
| 5 | ✅ Keep showing during fullscreen media | General ▸ "Keep showing while media plays" (on): over a fullscreen app the island stays while media plays from another app. A fullscreen video of the playing app still hides it. | `LiveActivity.keepsIslandInFullscreen` + `FullscreenVisibility` (tested). |

**Status:** ✅ M2 complete except Spotify likes (28 Oct 2026). Idle 0.000% CPU, playing 0.017% compact / 0.317% expanded (perl helper included, 0.000%), 21–22 MB. Screenshots in `docs/screenshots/m2/`. Still to try with Charlie at the Mac: Music, Spotify, Safari and Podcasts as real sources; the Music/Spotify **fallback's AppleScript** (state, artwork, favourite), which has only been exercised with no scriptable player running; the heart's permission prompt and a deny → re-allow; ±15 s on a long YouTube video; AirPods unplug; sleep/wake.

---

## M3: Status, alerts and live activities

> **Split:** M3a = #25, #26, #27, #29, #37, #38 (prompt `docs/prompts/M3a-*`). M3b = call, screen recording, downloads, #30, #31, #8, **plus the HUD (#20, #21, #23, formerly M5)**. Prompt: `docs/prompts/M3b-system-activities-and-hud.md`.

**Status (28 Oct 2026):** M3a (#25, #26, #27, #29, #37, #38) is built and verified on the Mac (branch `m3a-status`): see the rows below and **M3a status** under the table. Spec: `docs/superpowers/specs/2026-10-28-m3a-status-design.md`. Decisions: ADR-0011 (whatever is playing stays primary), ADR-0012 (banner pipeline), ADR-0013 (what the assumptions turned out to be on macOS 27.2). M3b (#8 priority, call, downloads, #31 camera/mic) is on branch `m3b-system`; screen recording and #30 Focus were spiked and set aside (ADR-0014, ADR-0015).

| # | Feature | Spec | Approach |
|---|---|---|---|
| 8 | ✅ User-adjustable priority | Settings ▸ Modules ▸ Priority: calls and screen recording are always first; you order Now Playing, timers/downloads/tools and Status, and pin modules above the rest (also "Pin Above Others" on a module's context menu). | `RankingPolicy`, a pure policy the coordinator ranks through (system, then pins, then your class order, then relevance and start order); saved by name, bad data falls back to the default. Not "feeds relevance": a relevance number can't say a timer beats music across classes (ADR-0016). Also: an activity that can't be hidden is never left hidden or only listed. |
| — | 🟨 "Call" system activity | "In a call" + duration for FaceTime, Phone, Zoom, Teams, Slack, Discord and Webex, as a non-hideable `system` activity that alerts once; a click opens the app. **No Mute/End**: none of these apps has a public route. Caller name and ringing aren't detectable. Off by default. | Per-process microphone use from the shared `SensorUsageService`, matched to a known-apps list; 1 s of mic use makes a call, a 3 s grace survives mic gaps, a quit ends it at once, only a call seen starting has a duration. Camera and mic dots on the call, and the call owns its mic so Camera & Microphone doesn't double up. **🟨 Verified with simulated readings and in unit tests; not yet with a real FaceTime, Zoom or Continuity call** (which process reports the mic for each is ADR-0017's open question). |
| — | ⏸ Screen recording (deferred, ADR-0014) | A red recording indicator with elapsed time and a **Stop** button, as a non-hideable `system` activity. | **Spiked, then deferred by Charlie (ADR-0014).** Detection works on 27.2 with no permission: SkyLight `SLSRegisterNotifyProc` types 1502/1503 fire for ⌘⇧5 and `screencapture -v`, never for screenshots. Stop is unsolved for ⌘⇧5, which ignores SIGINT; ⌘⌃Esc via `CGEvent` is untried. |
| — | 🟨 Downloads | Progress for browser downloads into `~/Downloads` as one activity: a ring (turning when the total is unknown) in compact and the bubble, up to three bar rows expanded, a "Done" banner you can click to show it in Finder. Off by default; asks for Files & Folders (Downloads) when turned on; its settings pane says what it can't see. | FSEvents on the folder (own queue; events deeper than the folder are dropped, so an unzip is a handful of scans) plus a scan per look; the progress xattr when a browser writes one; speed from growth. No `Progress` subscriber (unverified; ADR-0018). **🟨 Tested with real temporary folders and simulated scans; not yet with real Safari, Chrome or Firefox downloads, or the real permission prompt.** |
| 25 | ✅ Caps Lock indicator | Banner on toggle: the Caps Lock glyph (green when on) and On / Off; rapid toggles restart one banner. Off by default. | `NSEvent` global + local monitors for `.flagsChanged` → `CapsLockReducer`. **Needs no permission** on 27.2: an untrusted app's global monitor gets modifier changes but never key presses (verified with a probe; ADR-0013). |
| 26 | ✅ Mac battery | Banners: Charging, Plugged In (a charge limit holding it), Charged, On Battery, Low Battery (two levels, default 20/10%, red). Optional `.passive` charging activity (Never / Until 80% / Until Full): battery glyph and %, a ring in the bubble, ring + time to full + watts expanded. Hidden on desktop Macs. | IOKit power-source run-loop source (no polling) → `BatteryReducer`. **Verified with the real charger:** banners follow macOS's switch by the 1 s settle (ADR-0013). |
| 27 | 🟨 Bluetooth connect toast | Connect and disconnect banners (disconnect dimmed) with the device's symbol and a short name ("AirPods Pro"). Settings can leave out accessories or disconnects. | Audio: the shared CoreAudio `AudioOutputService`. Keyboards, mice, trackpads, controllers: I/O Registry matching notifications for Bluetooth HID devices. **No permission and no prompt** (verified; ADR-0013). Real AirPods connects verified. 🟨 **Keyboards and mice not yet seen with a real device** (none connected during testing); the Bluetooth permission is never asked, so "deny it" doesn't apply. |
| 29 | ✅ Wi-Fi / network | Banners for Wi-Fi (with the network's name, optional), Ethernet, Personal Hotspot and Offline, settled 2 s and at most 3 a minute. | `NWPathMonitor` on a utility queue → `NetworkReducer`. The name needs Location (asked only by its toggle; Hardened Runtime location entitlement). **Verified:** repeated Wi-Fi off/on gave two banners, no spam. |
| 30 | ⏸ Focus / Do Not Disturb (dropped from M3b) | Show the current Focus with its symbol. | **Spiked, then dropped by Charlie (ADR-0015).** On 27.2 the `_NSDoNotDisturb*` notifications never arrive, and `INFocusStatusCenter` reports false even when allowed. Only an App Intents Focus Filter works, and only for Focuses where the user added it. No Full Disk Access. |
| 31 | 🟨 Camera / mic in use | Orange dot and glyph for the microphone, green for the camera, on by default (needs no permission). `.live`, not hideable while the camera is on. Expanded names only apps proven to use the microphone ("An app" otherwise) and never the camera's owner. | CoreMediaIO and CoreAudio property listeners on a private queue, off the main thread; a running input device only *triggers* a look, the mic counts as in use when a process other than Notched has an input stream running. 500 ms debounce both ways. **🟨 Verified with simulated readings; reading the state causes no prompt (ADR-0017); real apps (Zoom, Safari, Voice Memos…) are not yet tried.** |
| 38 | ✅ Keep-awake | From Home, the status menu or its activity: 30 min, 1 hr, 2 hr, Indefinitely, Turn Off. Compact: a cup and the countdown; the bubble shrinks past an hour. Never restored after a relaunch. | One `PreventUserIdleDisplaySleep` assertion via `KeepAwakeReducer`. **Verified with `pmset -g assertions`:** held while on; released on Turn Off, quit, and switching the module off (10 cycles, none left). |
| 37 | ✅ Timers | Up to 10 timers and a stopwatch as `.live` activities: ring + time compact, the countdown in the bubble, an alert expansion with a system sound when done (the sound plays even with alert expansion off), then Recent. Presets 1/5/10/25 min and a Custom stepper (hold or scroll), +1 min, pause, cancel. Start from Home, the status menu or `notched://timer?minutes=10&label=Tea` (Release too). | `Date`-based `TimersReducer`; one `OneShotTimer` on the continuous clock plus a wake re-check; saved as `timers.state`. The ring is a Core Animation `strokeEnd` animation in the render server (ADR-0010). **Verified:** URL, ring, done alert, quit/relaunch. A finished timer rings for a minute or until Stop, so an alert that has to wait still shows. Links are rate-limited (ADR-0013). |


**M3a status (28 Oct 2026):** built and verified on macOS 27.2 (Mac16,13), branch `m3a-status`. Measured with `scripts/cpu.sh` over 60 s, Debug build, all M3a modules on:

| State | CPU (Notched + adapter helper) | Footprint | Budget |
|---|---|---|---|
| Idle, nothing live | **0.017%** | 27 MB | < 0.5% |
| Now Playing compact | **0.000%** | 31 MB | < 1.5% |
| A timer running, compact | **0.417%** (the system-ticked digits; the ring runs in the render server) | 31 MB | < 1% |

Robustness: sleep/wake wasn't tried physically (the timer and ring re-check on wake, and Network/Bluetooth stay quiet for 8 s after it; `WakeQuiet` and the timers' wake path are unit-tested); quit and relaunch with a running timer (restored; keep-awake not restored, its assertion released at quit); every module switched off and on 10 times (no assertion, thread or file-descriptor leak); real charger, AirPods and Wi-Fi off/on banners. Crash protection checked on the Mac (ADR-0013). Screenshots in `docs/screenshots/m3a/`.
**M3b Part A status (29 Oct 2026):** built on branch `m3b-system`; screenshots in `docs/screenshots/m3b/`; decisions in ADR-0014 to ADR-0018. Screen recording (detection works, Stop doesn't for ⌘⇧5) and Focus (#30; only a per-Focus filter works) were spiked and set aside by Charlie. Measured with `scripts/cpu.sh` on a Debug build, 45–60 s windows, on macOS 27.2 (Mac16,13):

| State | CPU (Notched + helper) | Footprint | Budget |
|---|---|---|---|
| M3b modules all off, nothing live (baseline) | **0.022%** | 40 MB | |
| Camera & Microphone, Calls and Downloads all on, idle | **0.017%** | 40 MB | < 0.5% |
| Each of the three on its own, idle | **0.000–0.022%** | 40 MB | |
| Mic + camera indicator showing | **0.000%** | 40 MB | |
| A call, compact (first minute, ticking each second) | **0.378%** | 32 MB | < 1% |
| A call + a 10-minute timer, compact | **0.622%** | 32 MB | < 1% |
| A download with progress, compact | **0.033%** | 40 MB | |
| A download with an unknown total (turning ring) | **0.100%** | 40 MB | |
| Release build: idle / a 10-minute timer | **0.022%** / 0.600% | 18 / 20 MB | |

- **A ticking duration costs about 0.6% each** (the same for a timer, whose M3a reading was 0.417% under quieter conditions). So a call's compact duration is seconds for the first minute and then whole minutes, redrawn once a minute (`CallClock`): call + timer fell from 1.27% to 0.62%. The expanded view keeps full seconds.
- Robustness: Camera & Microphone, Calls and Downloads each switched off and on 10 times in the running app: file descriptors 55 → 55, threads 9 → 7; each shell is also checked 5× in `ModuleShellTests` (no listener, stream, claim or activity left behind). Calls' claims are cleared on stop even while Camera & Microphone keeps the service alive.
- Denied permission: the Downloads pane shows "Not Allowed" with Open System Settings, and nothing is watched. Not yet tried: sleep/wake mid-download and mid-call (the reducers' wake paths are unit-tested), and the real macOS prompt.
- **For Charlie to try at the Mac** (the end-of-Part-A list): a real call in FaceTime, Zoom and a browser (which process reports the mic), muting for 10 s (does the 3 s grace hold), Voice Memos and Dictation as "other apps", a real download in Safari, Chrome and Firefox, and accepting then denying the Downloads prompt.

---

## M4: Productivity and developer tools

> **Split:** M4a = expanded tabs framework, Activity API, #62, #63 (prompt `docs/prompts/M4a-activity-api-and-claude-code.md`). M4b = the rest.

**M4a status (30 Oct 2026): 🟨 written and unit-tested, not yet run on the Mac.** The tab host (ADR-0020) was built and verified on the Mac earlier. The rest was written in a Linux cloud session with no Xcode: the pure logic (HTTP parser, security guard, tokens, gateway pipeline, payload validation, reducers, settings merger, installer against real temp files, usage parser/aggregator/service against real temp files) compiles and passes **146 tests on a Swift 6.0.3 toolchain**, including fuzz tests. The AppKit/SwiftUI/Network/FSEvents code (the listener, views, panes, module shells) has **not been compiled**; expect a round of compile fixes. Nothing here was measured for CPU or memory, and there are no screenshots. Run `docs/M4A-MAC-CHECKLIST.md` to close it. Decisions: ADR-0021 (API security), ADR-0022 (hook protocol), ADR-0023 (usage parsing). Reference: `docs/ACTIVITY-API.md`. Spec: `docs/superpowers/specs/2026-10-29-m4a-activity-api-claude-code-design.md`.

| # | Feature | Spec | Approach |
|---|---|---|---|
| 45 | Clipboard history | Expanded tab: search, pin, type icons (text, image, file, URL), source-app icon, ⌘⇧V hotkey, click to copy back. Settings: history length, excluded apps, ignore concealed/password items, clear on quit. | Poll `NSPasteboard.changeCount` through RefreshScheduler (~0.5 s while active; fine). Skip items marked `org.nspasteboard.ConcealedType` or `TransientType`. Expect macOS's pasteboard-privacy prompt and explain it in onboarding. Store history with SwiftData or a small SQLite file in Application Support. Never auto-paste with `CGEvent.post` by default. |
| 48 | Calendar | Compact countdown to the next event (≤ 15 min). Expanded agenda for today and tomorrow, with calendar colours. | EventKit full access (`NSCalendarsFullAccessUsageDescription`). Listen for `EKEventStoreChanged`. Include **one-click Join**: detect Zoom/Meet/Teams/Webex URLs in the event location, URL and notes (this is feature #49, cheap to add). |
| 50 | Reminders | Expanded list of today's and overdue reminders, with checkboxes that complete them. | EventKit, `NSRemindersFullAccessUsageDescription`. |
| 51 | Weather | Compact temperature and condition symbol (optional). Expanded: current conditions, hourly forecast, high/low. | **Open-Meteo** (free, no key). Location via CoreLocation (approximate is enough), or a manual city setting for people who refuse Location. Refresh every 30 min only while it matters; cache. |
| 55 | Colour picker | A button in the expanded tools row starts a system eyedropper. The result shows the swatch plus HEX/RGB/HSL with copy buttons, and keeps a recent-colours row. | `NSColorSampler` (public, no Screen Recording permission needed). |
| 62 | 🟨 Claude Code usage | Expanded "AI" tab: today's and this week's Claude Code token usage and estimated cost, plus active sessions. | **Free, local, no login:** parse Claude Code's session logs (JSONL under `~/.claude/projects/`; inspect the actual files and check the format before writing the parser), with a unit-tested parser. Use FSEvents to watch for changes. Plan-limit percentages are **optional and later**: the only source is an undocumented endpoint, so ask Charlie before touching any credentials. Never read or store OAuth tokens in M4. |
| 63 | 🟨 Coding-agent status + approve/deny | While Claude Code works, the compact island shows "Claude is working…" with the project name. When Claude Code asks for permission, the island expands with the tool request and **Allow / Deny** buttons. A notification shows when the agent finishes. | **Claude Code hooks** (check the current hooks docs for the event names, e.g. PreToolUse / PermissionRequest / Notification / Stop). A small helper CLI (`notched-hook`, installed by the app into `~/.local/bin`) sends hook events through the **Activity API** (below; a Unix domain socket in Application Support is the fallback), and for approval requests waits for the reply. Study farouqaldori/vibe-notch (Apache-2.0) for the pattern. The app offers a one-click "Install Claude Code hooks" that edits `~/.claude/settings.json` safely (back it up first, merge, never clobber). The socket must be user-only (0600). |
| — | 🟨 Activity API | Third-party tools post live activities: a `notched://` URL scheme for one-shots, and a localhost-only HTTP endpoint with **per-client tokens** (and optionally XPC) for live updates. Payloads map onto `LiveActivity` regions with a small set of templates. | Its own module with a settings pane to approve and revoke clients. #63's Claude Code hooks use this API rather than a private socket. §7. |
| 64 | Terminal in the notch | An expanded "Terminal" tab hosting a real shell. | **SwiftTerm** (MIT) `LocalProcessTerminalView`. Typing needs key status: when the terminal tab is focused, allow the panel to become key temporarily, and drop key status on collapse. Esc collapses. |
| 71 | Layout editor | Choose which modules appear in the compact leading/trailing slots and the order of the expanded tabs, by drag and drop in Settings. | Persist in SettingsStore and feed into ActivityCoordinator priority. |

---

## M3b (Part B): HUD replacement (formerly M5, merged into M3b)

| # | Feature | Spec | Approach and risk |
|---|---|---|---|
| 20 | Volume HUD | Pressing the volume keys shows the volume in the island (bar + speaker symbol + output device icon) and the system HUD does not appear. | Active `CGEventTap` for system-defined media-key events (NX_KEYTYPE_SOUND_UP/DOWN/MUTE); **needs Accessibility**. Set the volume yourself through CoreAudio and swallow the event. On macOS 26+ the system HUD lives in Control Center: confirm on 27.2 whether swallowing the key is enough to suppress it. Study dannystewart/volumeHUD (MIT). **Fail-safe:** if the volume didn't change, pass the event through; re-enable the tap on timeout. Also support Shift+Option fine steps (quarter increments, like macOS). |
| 21 | Brightness HUD | Same for display brightness on the built-in display. | Private DisplayServices (`DisplayServicesGetBrightness/SetBrightness`) via a `dlopen` wrapper. Experimental: hide the option if the symbols aren't found. |
| 23 | HUD styles | Styles: inline-in-notch (default), vertical, circular, minimal. | Pure SwiftUI once #20 works. |

**M3b Part B status (29 Oct 2026):** built on branch `m3b-system`; decisions in ADR-0019; screenshots in `docs/screenshots/m3b-hud/`; plan `docs/superpowers/plans/2026-10-29-m3b-hud.md`; safety design `docs/superpowers/specs/2026-10-29-m3b-hud-tap-safety-design.md`. Measured on macOS 27.2 (Mac16,13), a Debug build, with synthetic key events (`notched://debug/hud-key`):

- **#20 volume HUD ✅ built, 🟨 real keys pending.** Swallowing the key at a session tap does suppress the Control Center HUD (no "Show alongside" needed). A 32-event hold: every event handled by the tap, callback median **1.5 ms**, p95 8.3 ms, max 9.2 ms (the breaker trips at 50 ms). Pausing mid-hold hands the rest to macOS cleanly. A key posted while the main thread was blocked for 2.5 s was handled 7 ms later. Module switched on and off 10 times: file descriptors 47 → 47, threads 7 → 6. Two crashes while armed (kill -9) start the HUD latched with no tap, and the pane says why. **Idle with the tap armed: 0.044% CPU, 19 MB** (Part A's baseline was 0.017–0.022%; budget < 0.5%). **During sustained bursts (11 keys/s for 25 s): 13.5% CPU and a peak of 83 MB**, of which the test harness itself is 1.0% and 22 MB; memory returns to 22 MB afterwards, and a profile shows SwiftUI attribute-graph updates and Swift metadata lookups (unoptimized-build costs), not CoreAudio or event handling. Worth re-measuring on a Release build with real key repeats.
- **#21 brightness HUD ⏸ waiting on one check.** Everything it needs is built (the reducer, engine and banner already handle brightness keys when armed), but the private DisplayServices wrapper and the option wait on whether F1 and F2 reach the tap as media-key events. With the HUD module on in a Debug build, press F1 and F2, then run `log show --last 1m --predicate 'category == "hud.tap"'`: key codes 2 and 3 mean yes (then #21 is built), no lines mean they're ordinary key presses and #21 is dropped (Charlie, 29 Oct).
- **#23 HUD styles ✅.** Inline, vertical, circular and minimal, a picker with a live preview in the module's pane, on the notch and the pill (`b3-*`); the HUD pre-empts music and the island hands it back (`b3-music-*`).
- **For Charlie to try at the Mac** (the end-of-Part-B list): real volume keys (tap, hold, mute, ⇧, ⇧⌥, ⌥), AirPods or another Bluetooth output (and switching outputs mid-press), an external display, a fullscreen video, revoking Accessibility while the HUD is on (the keys must keep working), the F1/F2 check above, and whether Accessibility alone is enough with Input Monitoring revoked.

---

## M6: Hard, fragile and polish

| # | Feature | Spec | Approach and risk |
|---|---|---|---|
| 17 | Per-app volume mixer | Expanded audio tab: a slider per app currently playing audio. | Core Audio process taps + aggregate devices (macOS 14.4+). Hard. Build a spike first and write an ADR. |
| 28 | AirPods / accessory battery | Show left, right and case battery on connect and in the expanded audio tab. | Private IOBluetooth properties via a wrapper, or BLE advertisement parsing with CoreBluetooth. Do **not** copy AirBattery (AGPL). Experimental, hidden if unavailable. |
| 59 | Lock-screen widgets | On the lock screen: Now Playing (artwork, controls), time-friendly widgets (battery, next event). Off by default. | Lakr233/SkyLightWindow (MIT) `moveToSky()`. **Follow the lock-screen safety rules in CLAUDE.md.** |
| 13b | Lyrics on the lock screen | The current lyric line below the lock-screen player. | Reuse #13 + #59. |
| 76 | Auto-updates | Check GitHub Releases. Stable and beta channels. | Sparkle 2 with an EdDSA-signed appcast hosted on GitHub Pages. Only worth it once the app is shared publicly, so **ask Charlie** before setting up keys. |

---

## Later / parked

- ⏸ **54 Teleprompter.** Wanted later: scrolling script under the camera, optionally voice-following (Speech framework).
- ⏸ **61 Face Unlock.** Parked: a third-party app cannot securely unlock macOS. It would need to store the password, and Mac cameras have no depth sensing, so a photo could spoof it. A possible safe alternative is "presence": the island greets you or wakes when you sit down, with no unlocking. Decide later.
- ⏸ **Mirror the Clock app's timers** (from #37). Private routes only; experimental (`docs/ISLAND-BEHAVIOR.md` §7).
- Ideas from the research worth considering after M6: 75 energy modes UI (the scheduler already exists), 40/41 file shelf + AirDrop, 53 webcam mirror.
- ✖ **Maps turn-by-turn.** Not possible on the Mac: Mac Maps has no live navigation, and although macOS Tahoe shows an iPhone's Live Activities in the menu bar, no API lets another app read them (only an untested Accessibility scrape). At most a later experiment (`docs/ISLAND-BEHAVIOR.md` §7).
