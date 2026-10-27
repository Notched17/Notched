# Roadmap

Feature numbers match the master checklist in `docs/research/notch-app-research.md`. Build the milestones in order. Each one should end with a working, installed app, passing tests, a performance check (see the budget in CLAUDE.md) and a git commit.

**Status key:** ⬜ not started · 🟨 in progress · ✅ done · ⏸ parked

---

## M1: Shell and foundations

Goal: a beautiful, stable island that appears in the right place on every display, morphs smoothly, and has the plumbing every later feature needs.

| # | Feature | Spec and acceptance criteria | Approach |
|---|---|---|---|
| 1 | Notch overlay, compact ↔ expanded | Hovering (with a short configurable delay) or clicking expands it, and it collapses when the pointer leaves. Expand/collapse is one continuous spring morph. Idle shows the bare notch (black, invisible against the hardware notch) or the pill on non-notch screens. | Borderless, non-activating, transparent `NSPanel` subclass: `canBecomeKey`/`canBecomeMain` false by default, level `.mainMenu + 3` (match boring.notch), and collectionBehavior `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Position it from `screen.frame` (not `visibleFrame`), top centre. `NotchGeometry`: a notch exists when `safeAreaInsets.top > 0`; width = `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width` (plus a small fudge); height = `safeAreaInsets.top`. Without a notch, use the menu-bar height for a pill. Rebuild on `NSApplication.didChangeScreenParametersNotification`. Study DynamicNotchKit (MIT) and boring.notch (GPL) for the window code. |
| — | Multi-display basics | One island per screen; the user chooses "main display only", "all displays" or a specific display. | One `IslandController` per `NSScreen`, keyed by display UUID. |
| 5 | Auto-hide in fullscreen | Hide when the frontmost app on that screen is fullscreen (games, video). Optional setting: keep showing during fullscreen media. | Watch active-space changes (`NSWorkspace.activeSpaceDidChangeNotification`) plus frontmost-app window bounds versus screen frame. Test with Safari video fullscreen and a fullscreen game. |
| 6 | Hide from screenshots/recordings (toggle) | Setting off by default. When on, the island doesn't appear in screenshots or screen sharing. | `panel.sharingType = .none`. Note in the UI that some capture tools may still see it. |
| 7 | Click-through around the island | Menu-bar items and app menus beside the notch stay clickable. Only the visible island shape takes clicks. | Keep the panel the size of the current island shape and resize it as the island morphs, or toggle `ignoresMouseEvents` with a global mouse-moved monitor and hit-testing. Hover must still work. Test the File/Edit menus of a wide-menu app. |
| 70 | Per-feature toggles | Modules pane in Settings: every module has a toggle, a description and its required permissions. | `ModuleRegistry` + `SettingsStore`. Disabled modules cost zero CPU. |
| 72 | Size, position, animation tuning | Sliders: island width offset, expanded size, hover delay, animation style (Snappy / Smooth / Bouncy) with a live preview. | Spring tokens in `DesignSystem`. |
| 73 | Materials and themes | Theme per display type: "Notch black" (default on notch), "Liquid Glass" (default on pill), "Tinted glass" (accent tint). Honour Reduce Transparency. | `.glassEffect`, `GlassEffectContainer`. See the design section of CLAUDE.md. |
| 77 | Menu-bar agent, launch at login, onboarding | `LSUIElement` app. Status item menu: Settings…, Pause island, About, Quit. "Launch at login" uses `SMAppService.mainApp`. The first-run onboarding is a short, beautiful 3–4 step window: welcome → choose modules → permissions (only for chosen modules) → done. | `PermissionCenter` shows the live status of each TCC permission, with a button that opens the right System Settings pane. |
| — | Infrastructure | `ActivityCoordinator` (with unit tests), `RefreshScheduler`, `PermissionCenter`, `os.Logger` subsystems, GPL LICENSE, `THIRD_PARTY_NOTICES.md`, `.gitignore`, `README.md`. | — |

**M1 demo module:** a tiny built-in "Hello" activity, triggered from a debug menu item, that proves activities flow through the coordinator into the compact and expanded views. Remove it or hide it behind a DEBUG flag later.

---

## M2: Media

| # | Feature | Spec | Approach and risk |
|---|---|---|---|
| 9 | Now Playing | Compact: album art (leading, small, rounded) and a live visualiser (trailing). Expanded: large artwork, title, artist, album, play/pause, previous/next, the source app's icon. Clicking the artwork opens the source app. Media gestures: horizontal two-finger swipe for next/previous. | A `NowPlayingProvider` protocol with backends (see #10). Artwork's dominant colour tints the expanded background subtly. |
| 10 | Any-app source detection | Works for Safari, Chrome, Podcasts, VLC and so on, not just Music/Spotify. | **ungive/mediaremote-adapter** (BSD-3): bundles a framework and runs `/usr/bin/perl` to read MediaRemote, because Apple blocked direct use in 15.4. Follow its README exactly and check its support for macOS 27. **Fallback backend:** AppleScript/ScriptingBridge for Music and Spotify; this needs `NSAppleEventsUsageDescription` and the `com.apple.security.automation.apple-events` entitlement. The provider picks the adapter if it works, otherwise the fallback. |
| 11 | Seek bar and ±15 s skip | Scrubbable progress bar with elapsed/remaining time (`.monospacedDigit()`), plus ±15 s buttons for podcasts. | The adapter exposes seek/skip commands. Interpolate the elapsed time locally from the timestamp and playback rate; don't poll. |
| 12 | Animated visualiser | 4–5 bars bounce while audio plays and settle to dots when paused. It looks alive, not random: per-bar phase-shifted sine with noise, and amplitude eases in and out on play/pause. A later option is real audio-reactive bars via Core Audio process taps (needs System Audio Recording permission). | `TimelineView(.animation)` or Canvas. **Pause completely when not visible** to protect the CPU budget. |
| 13 | Synced lyrics (notch part) | The current lyric line shows under the expanded player and optionally as a compact ticker. Lock-screen lyrics come in M6. | LRCLIB API (`lrclib.net/api/get` by track, artist, album and duration). Parse LRC with a unit-tested parser and cache results on disk. **Only query when lyrics are enabled** (Atoll leaked track names when the feature was off). |
| 15 | Like / favourite the song | A heart button. | Apple Music: AppleScript (`favorited`/`loved` property; check which one works on macOS 27). Spotify: needs the Spotify Web API with OAuth PKCE and the user's own free developer app; **stop and ask Charlie** before building the Spotify part. |
| 16 | Output device switcher | Expanded player shows the current output (AirPods, speakers…) with an icon, and a menu to switch output devices. | CoreAudio `kAudioHardwarePropertyDefaultOutputDevice`, a device list, and a property listener for changes. |

---

## M3: Status, alerts and live activities

| # | Feature | Spec | Approach |
|---|---|---|---|
| 8 | Several activities + priority | Finish the coordinator: queue transient alerts, show two compact items (leading/trailing), add a "Live activities" list in the expanded view, and add user-adjustable priority. | Already scaffolded in M1. |
| 25 | Caps Lock indicator | Small transient compact alert on toggle. | `NSEvent` global monitor for `.flagsChanged`. |
| 26 | Mac battery | Alerts when charging starts or stops, at low battery (20/10%, configurable) and when full. Expanded view shows % and time remaining. Hidden on desktop Macs. | IOKit `IOPSNotificationCreateRunLoopSource` and `IOPSCopyPowerSourcesInfo`. |
| 27 | Bluetooth connect toast | "AirPods Pro connected" with a device-type SF Symbol. | IOBluetooth connection notifications (`IOBluetoothDevice.register(forConnectNotifications:)`) or CoreAudio device added/removed for audio devices. Needs the Bluetooth permission. |
| 29 | Wi-Fi / network | Toast when the connection drops or changes (Wi-Fi ↔ Ethernet ↔ offline). | `NWPathMonitor`. The SSID needs the Location permission on modern macOS, so make it optional. |
| 30 | Focus / Do Not Disturb | Show the current Focus with its symbol. | **No public API.** Research what works on macOS 27 first (assertions file under `~/Library/DoNotDisturb/DB/` needs Full Disk Access; or an App Intents / Focus Filter approach). Write the findings to an ADR and **ask Charlie** if it needs Full Disk Access. |
| 31 | Camera / mic in use | Green/orange dot plus an icon when any app uses the camera or mic, debounced. | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` and CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`, with property listeners. Debounce by 500 ms to stop false toggles. |
| 38 | Keep-awake | A toggle in the expanded view and a compact coffee-cup indicator while active. Duration presets: 30 min, 1 h, 2 h, indefinitely. | `IOPMAssertionCreateWithName` (`PreventUserIdleDisplaySleep`). Always release it on quit. |

---

## M4: Productivity and developer tools

| # | Feature | Spec | Approach |
|---|---|---|---|
| 45 | Clipboard history | Expanded tab: search, pin, type icons (text, image, file, URL), source-app icon, ⌘⇧V hotkey, click to copy back. Settings: history length, excluded apps, ignore concealed/password items, clear on quit. | Poll `NSPasteboard.changeCount` through RefreshScheduler (~0.5 s while active; fine). Skip items marked `org.nspasteboard.ConcealedType` or `TransientType`. Expect macOS's pasteboard-privacy prompt and explain it in onboarding. Store history with SwiftData or a small SQLite file in Application Support. Never auto-paste with `CGEvent.post` by default. |
| 48 | Calendar | Compact countdown to the next event (≤ 15 min). Expanded agenda for today and tomorrow, with calendar colours. | EventKit full access (`NSCalendarsFullAccessUsageDescription`). Listen for `EKEventStoreChanged`. Include **one-click Join**: detect Zoom/Meet/Teams/Webex URLs in the event location, URL and notes (this is feature #49, cheap to add). |
| 50 | Reminders | Expanded list of today's and overdue reminders, with checkboxes that complete them. | EventKit, `NSRemindersFullAccessUsageDescription`. |
| 51 | Weather | Compact temperature and condition symbol (optional). Expanded: current conditions, hourly forecast, high/low. | **Open-Meteo** (free, no key). Location via CoreLocation (approximate is enough), or a manual city setting for people who refuse Location. Refresh every 30 min only while it matters; cache. |
| 55 | Colour picker | A button in the expanded tools row starts a system eyedropper. The result shows the swatch plus HEX/RGB/HSL with copy buttons, and keeps a recent-colours row. | `NSColorSampler` (public, no Screen Recording permission needed). |
| 62 | Claude Code usage | Expanded "AI" tab: today's and this week's Claude Code token usage and estimated cost, plus active sessions. | **Free, local, no login:** parse Claude Code's session logs (JSONL under `~/.claude/projects/`; inspect the actual files and check the format before writing the parser), with a unit-tested parser. Use FSEvents to watch for changes. Plan-limit percentages are **optional and later**: the only source is an undocumented endpoint, so ask Charlie before touching any credentials. Never read or store OAuth tokens in M4. |
| 63 | Coding-agent status + approve/deny | While Claude Code works, the compact island shows "Claude is working…" with the project name. When Claude Code asks for permission, the island expands with the tool request and **Allow / Deny** buttons. A notification shows when the agent finishes. | **Claude Code hooks** (check the current hooks docs for the event names, e.g. PreToolUse / PermissionRequest / Notification / Stop). A small helper CLI (`dynamicnotch-hook`, installed by the app into `~/.local/bin`) sends hook events over a **Unix domain socket** in Application Support, and for approval requests waits for the reply. Study farouqaldori/vibe-notch (Apache-2.0) for the pattern. The app offers a one-click "Install Claude Code hooks" that edits `~/.claude/settings.json` safely (back it up first, merge, never clobber). The socket must be user-only (0600). |
| 64 | Terminal in the notch | An expanded "Terminal" tab hosting a real shell. | **SwiftTerm** (MIT) `LocalProcessTerminalView`. Typing needs key status: when the terminal tab is focused, allow the panel to become key temporarily, and drop key status on collapse. Esc collapses. |
| 71 | Layout editor | Choose which modules appear in the compact leading/trailing slots and the order of the expanded tabs, by drag and drop in Settings. | Persist in SettingsStore and feed into ActivityCoordinator priority. |

---

## M5: HUD replacement

| # | Feature | Spec | Approach and risk |
|---|---|---|---|
| 20 | Volume HUD | Pressing the volume keys shows the volume in the island (bar + speaker symbol + output device icon) and the system HUD does not appear. | Active `CGEventTap` for system-defined media-key events (NX_KEYTYPE_SOUND_UP/DOWN/MUTE); **needs Accessibility**. Set the volume yourself through CoreAudio and swallow the event. On macOS 26+ the system HUD lives in Control Center: confirm on 27.2 whether swallowing the key is enough to suppress it. Study dannystewart/volumeHUD (MIT). **Fail-safe:** if the volume didn't change, pass the event through; re-enable the tap on timeout. Also support Shift+Option fine steps (quarter increments, like macOS). |
| 21 | Brightness HUD | Same for display brightness on the built-in display. | Private DisplayServices (`DisplayServicesGetBrightness/SetBrightness`) via a `dlopen` wrapper. Experimental: hide the option if the symbols aren't found. |
| 23 | HUD styles | Styles: inline-in-notch (default), vertical, circular, minimal. | Pure SwiftUI once #20 works. |

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
- Ideas from the research worth considering after M6: 75 energy modes UI (the scheduler already exists), 40/41 file shelf + AirDrop, 37 timers, 53 webcam mirror.
