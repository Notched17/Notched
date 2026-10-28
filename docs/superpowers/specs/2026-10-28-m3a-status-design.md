# M3a Status modules: design

- Date: 2026-10-28
- Brief: `docs/prompts/M3a-status-alerts.md`. Step 0 plan approved by Charlie on 28 Oct, with these answers:
  1. Work split **(a)**. A cloud session (Linux, no Xcode) writes Step 1 and every pure reducer with its tests. The modules' UI, screenshots, robustness and performance follow in a local session on the Mac.
  2. **Defaults:** Timers and Keep-awake are on. The banner modules (Battery, Bluetooth, Network) are on for new installs and switched on once for existing installs. Caps Lock is off (it needs Accessibility). CLAUDE.md is updated to match.
  3. **Music stays primary.** Whatever is playing keeps the island; timers, keep-awake and charging show as bubbles beside it. For any similar call, follow what Apple does.
  4. Rewrite the CPU script and test player (the originals stayed in the M2 session's scratchpad).
  5. Bluetooth shows **connect and disconnect** banners, for **every kind of Bluetooth device** possible.
  6. A timer that finished while Notched wasn't running: one silent alert if it ended in the last 10 minutes, otherwise straight to Recent.
  7. Caps Lock may need Accessibility: off by default, and it asks when switched on.
- Builds on: ADR-0006 (activity model), ADR-0007 (bubbles), ADR-0008 (reducer + backend pattern), `docs/ISLAND-BEHAVIOR.md` §1, §2 and §4.

## Intent

The small, always-useful status features from iPhone's Dynamic Island: the charging banner, AirPods connecting, Silent mode, plus timers and keep-awake. Each costs nothing when off and next to nothing when on. Each follows Now Playing's shape: a thin system shell around a pure, tested reducer. The work starts with the foundations M2's review asked for, so six new modules don't each reinvent lifecycle, crash safety and banner throttling.

## Decisions

### 1. Ranking: media above live (supersedes part of ADR-0006, see ADR-0011)

`ActivityKind` becomes `passive < live < media < system`. Now Playing (and later any media) keeps the attached island. A timer, keep-awake or download shows as a minimal bubble beside it, and takes the island when nothing plays. Calls and screen recording still win. The ordering tests and `docs/ISLAND-BEHAVIOR.md` §2 change with it. User-adjustable priority (#8) stays in M3b.

| Activity | Kind | Relevance |
|---|---|---|
| Timer (running) | `.live` | 30, plus a tiebreak so the soonest-ending timer wins |
| Timer (paused) | `.live` | 20 |
| Stopwatch | `.live` | 15 |
| Keep-awake | `.live` | 10 |
| Battery while charging (opt-in) | `.passive` | 0 |

### 2. `ModuleHost`: lifecycle out of `applySettings`

Today `AppEnvironment.applySettings` calls `modules.reconcile` inside `withObservationTracking`. A setting a module reads in `start()` is therefore tracked by that closure, and changing it re-runs the whole settings push.

- **`ModuleHost`** (`Sources/Core/Modules/ModuleHost.swift`, `@MainActor @Observable`) owns the running modules. It observes **only** `settings.enabledModules`, and reconciles outside the tracking closure.
  - **Order:** stops before starts. Stops run in reverse start order; starts run in catalogue order. `endAll(from:)` follows each stop.
  - **`stopAll()`** on quit, in reverse start order.
- **`ModuleRegistry`** keeps its API (catalogue, settings panes, `isRunning`, `module(_:)`, `runningIDs`, `reconcile`), but forwards lifecycle to its host. Settings and the existing tests don't change.
- **`ModuleLifecyclePlan.make(running:enabled:catalogOrder:blocked:)`** is pure and works out what to stop and start.
- **`ModuleServices`** goes into `ModuleContext`. It holds the shared `AudioOutputService` (reference-counted `acquire()`/`release()`, so Now Playing and Bluetooth share one set of CoreAudio listeners), the `PermissionCenter`, and `previousSessionCrashed`.
- **Crash-loop protection** (`LaunchGuard`, pure, persisted as `LaunchRecord` JSON in UserDefaults):
  - **Session.** Each launch opens a session. A clean quit (including SIGTERM) closes it. A session still open at the next launch means the app crashed or was killed.
  - **Per-module.** The host writes `startingModule` before each `start()` and clears it after. A module still marked at launch gets a strike. **Two strikes suspend it.** Settings then says it was turned off because it quit unexpectedly while starting, with a Turn On button (`resume`).
  - **App-wide.** A session that crashes before it has been up 30 s is a quick crash. **Three quick crashes within 10 minutes → safe mode:** no module starts, and the status menu offers "Resume Modules". Safe mode is never entered while a debugger is attached, because Xcode's Stop button kills the app.
  - **Stability.** 30 s after launch the session is marked stable, and the running modules' strikes are cleared.
  - **`previousSessionCrashed`** is available to modules. Keep-awake uses it now (it never restores itself); lock-screen features in M6 will too.
- **Defaults.** `ModuleDescriptor.isOnByDefault` plus a persisted `modules.seen` set. `ModuleDefaults.apply` (pure) switches on each default-on module the user has never seen, exactly once. A module the user turned off stays off.

### 3. Reducer convention

Every live module has a pure, unit-tested reducer: `mutating func reduce(_ event: Event, now: Date) -> [Effect]`. It holds no system types and no SwiftUI. The module is a thin shell: it turns system callbacks into `Event`s and carries out the `Effect`s. Media's `MediaActivityReducer` is the worked example and stays as it is. The CLAUDE.md module contract says so, and `docs/templates/module-reducer.md` has the template.

### 4. Banner pipeline

Banners (ADR-0012) are short system events. They never take a minimal slot.

- **`BannerSource<Value>`** (pure, `Sources/Core/Activities/BannerSource.swift`) turns a stream of states into the banners worth showing:
  - `seed(_:)` sets the starting state without a banner.
  - `receive(_:at:)` and `advance(to:)` return `.emit(Value)`, `.wake(Date)` or `.none`.
  - **Policy:** `settle` (a change must last this long), `cooldown` (the same value isn't announced again within it) and `maxPerWindow`/`window` (a rate limit).
  - **Flaps:** a change that reverts within `settle` emits nothing. When the rate limit holds a change back, only the **latest** state is announced once allowed, never the steps in between.
- Each module's reducer embeds its `BannerSource` and returns its wakes as `.wake(Date)` effects for the module's one `OneShotTimer`. A separate emitter class would add nothing.
- **`BannerContent`** gives every banner one look, like iPhone's Silent and charging banners:
  - **Leading:** a symbol (hierarchical, tinted, bounces once) and a short label, e.g. "Charging".
  - **Trailing:** a value ("82 %", "On") or a tinted glyph, `.monospacedDigit()`.
  - **Battery:** a small battery glyph filled to the level.
- **`TransientBanner.priority`** (`.low`, `.normal`, `.high`), default `.normal`.
- **`BannerQueue`** (pure) replaces the coordinator's single waiting slot:
  - It holds up to 3 waiting banners. A banner with the same `id` replaces its queued copy, so ids act as categories ("network", "battery.power", "capslock", "bluetooth.<device>").
  - **Order:** priority, then arrival.
  - **Expiry:** a waiting banner is dropped after 5 s, or 30 s for `.high` (low battery).
- **Banners and alerts:**
  - Banners wait while an alert expansion shows or the user is on the island (unchanged).
  - **An alert that arrives during a banner cuts the banner short.** On iPhone, an expanding activity takes the whole island. The cut banner isn't shown again.
- **Policies:**

  | Banner | Settle | Cooldown | Rate limit | Priority |
  |---|---|---|---|---|
  | Network | 2 s | — | 3 per 60 s | normal |
  | Charger plugged/unplugged | 0 | 10 s for the same state (a loose connector) | — | normal |
  | Low battery | 0 | once per crossing (hysteresis +3 %) | — | high |
  | Bluetooth connect | 1 s, to merge the audio and input views of one device | — | — | normal |
  | Bluetooth disconnect | 2 s (a reconnect blip announces nothing) | — | — | low |
  | Caps Lock | 0 | — | none (same id restarts) | normal |

### 5. Modules

Each module has its own folder under `Sources/Modules/`, a reducer, a `<Name>Settings` child of `SettingsStore`, a section in Settings ▸ Modules, and an on/off toggle. A module that is off creates nothing.

#### #26 Battery (on by default; hidden on Macs without a battery)

- **Source:** `IOPSNotificationCreateRunLoopSource` → `IOPSCopyPowerSourcesInfo` (level, charging, AC, charged, time to empty or full), plus `IOPSCopyExternalPowerAdapterDetails` (watts). No polling.
- **Reducer `BatteryReducer`:**
  - **State:** `power` (`.battery`, `.charging`, `.onHold` (plugged in, not charging, not full: Optimised Charging or a charge limit), `.charged`), `level`, armed low thresholds, and whether the activity is posted.
  - **Banners:**
    - "Charging 82 %" (green bolt)
    - "Charging On Hold"
    - "Fully Charged"
    - "On Battery 64 %" (unplugged)
    - "Low Battery 20 %" / "10 %" (thresholds configurable, default 20 and 10; red, `.high`)
  - The first snapshot is silent.
- **Live activity:** optional ("Show while charging": Off (default) / Until 80 % / Until 100 %). A `.passive` activity, so it sits beside music. Compact: a battery glyph with a bolt, and the percentage. Minimal: a small level ring. Expanded: a level ring, time to full or empty, power source, and charger watts when known.

#### #27 Bluetooth (on by default)

- **Audio devices:** CoreAudio, through the shared `AudioOutputService` (M2's device list and symbol mapping). No permission.
- **Every other device** (keyboards, mice, trackpads, game controllers): IOKit registry matching notifications for `IOHIDDevice` services whose `Transport` is Bluetooth or Bluetooth Low Energy (`IOServiceAddMatchingNotification` first-match and terminated). This reads the I/O Registry only, so it needs **no permission**: not Bluetooth, and not Input Monitoring. IOBluetooth would need the Bluetooth permission and doesn't see BLE accessories. If the IOKit route fails on 27.2, the fallback is IOBluetooth behind the Bluetooth permission, requested from the module's pane.
- **Reducer `BluetoothReducer`:**
  - Devices are keyed by Bluetooth address when either source knows it (the CoreAudio UID and the HID `DeviceAddress` both carry it), otherwise by name. A device is connected while any source reports it.
  - Connect is announced once its 1 s settle passes, using the best symbol (audio beats input).
  - Disconnect is announced when the last source has been gone for 2 s.
  - The starting device list is silent. Built-in, virtual and aggregate audio devices are ignored.
- **Banners:**
  - Connected: "AirPods Pro" plus a symbol, trailing "Connected".
  - Disconnected: the same, dimmed, trailing "Disconnected".
  - Ids are `bluetooth.<key>`, so connecting and disconnecting the same device replace each other.
- **Symbols:** from M2's mapping for audio devices. Keyboard → `keyboard`, mouse → `magicmouse` (Apple) / `computermouse`, trackpad → `rectangle.and.hand.point.up.left`, game controller → `gamecontroller`, other → `wave.3.right`.

#### #29 Network (on by default)

- **Source:** `NWPathMonitor` on a utility queue. A `Sendable` `NetworkState` (`.wifi(ssid?)`, `.ethernet`, `.hotspot` (an expensive path), `.other`, `.offline`) is passed to the main actor.
- **Reducer `NetworkReducer`:** a `BannerSource` with a 2 s settle and at most 3 banners per minute. The starting path is silent.
- **Banners:**
  - "Wi-Fi" + network name, or "Connected" (`wifi`)
  - "Ethernet" + "Connected" (`cable.connector`)
  - "Personal Hotspot" (`personalhotspot`)
  - "Offline" (`wifi.slash`)
- **Wi-Fi name:** the "Show Wi-Fi name" sub-toggle is off by default. Turning it on requests Location ("When In Use"). The app needs the Hardened Runtime entitlement `com.apple.security.personal-information.location`. If Location is denied, the banner says "Connected" and the pane shows a fix-it row. The name is read with `CWWiFiClient` only on a path change.

#### #25 Caps Lock (off by default)

- **Source:** `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`. Apple documents key-event monitoring as needing Accessibility. If 27.2 confirms that, the pane says why, and switching the module on asks for Accessibility. It never uses Input Monitoring.
- **Reducer `CapsLockReducer`:** announces only real toggles; Shift and Command presses are ignored. The starting state is silent.
- **Banner:** `capslock.fill` "Caps Lock" "On" / `capslock` "Caps Lock" "Off". The same id is reused, so rapid toggles restart one banner.

#### #38 Keep-awake (on by default; does nothing until used)

- **Source:** `IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep)` behind a `PowerAssertionClient` protocol (faked in tests).
- **Reducer `KeepAwakeReducer`:**
  - **State:** `.off` or `.on(until: Date?)`, and `assertionHeld`.
  - **Rules:** acquire once; a preset change reschedules without a second acquire. Stop, expiry, a wake past the end, or quit releases. Indefinite has no deadline.
  - **Invariant (fuzz-tested):** at most one assertion is held, and none after quit.
- **No persistence.** Quit means off. A crash releases the assertion in the kernel, and `previousSessionCrashed` stops it from being restored.
- **Presentation:**
  - **Compact:** `cup.and.saucer.fill`; trailing the countdown (`Text(timerInterval:)`), or "On" when indefinite.
  - **Minimal:** the countdown, or the cup.
  - **Expanded:** state, end time, the presets, Turn Off.
  - **Elsewhere:** a Home quick action, and Keep Awake ▸ (30 min, 1 h, 2 h, Indefinitely, Turn Off) in the status menu. `.live`, hideable.

#### #37 Timers and stopwatch (on by default)

- **Reducer `TimersReducer`:**
  - **State:** `[TimerItem]` (`id`, `label`, `duration`, phase `.running(endsAt)` / `.paused(remaining)` / `.done(at)`), and an optional `Stopwatch` (`startedAt`, `accumulated`, `isRunning`).
  - **Events:** start, pause, resume, +1 min, cancel, deadline, wake, restore, plus stopwatch start, pause, reset.
  - **Effects:** post, end, alert, play sound, schedule the earliest deadline, persist.
  - **Completion:** post "Done" with an alert, play the chosen system sound (default "Glass"; played by the module, so it rings even with alert expansion off), then end into Recent after the alert's duration. Ending at once would cancel the alert.
  - **Relaunch:** running timers resume. A timer that ended in the last 10 minutes alerts once, silently ("Ended at 14:05"). Older ones go straight to Recent.
- **Time is `Date`-based.** One `OneShotTimer` at the earliest deadline (`Task.sleep` runs on the continuous clock, so it counts sleep), plus a re-check on `NSWorkspace.didWakeNotification`. Digits use `Text(timerInterval:pauseTime:countsDown:)`, which the system ticks, with `.monospacedDigit()`. No per-second work of ours.
- **Ring:** a `CAShapeLayer` with one `strokeEnd` animation from the current progress to 0 over the time left, so it runs in the render server. It's removed when the view leaves its window or the window is covered, and rebuilt from the dates when it returns (the `MediaVisualizer` pattern). It still moves with Reduce Motion, because it carries information like the Clock app's ring.
- **Presentation:**
  - **Compact:** the ring on the leading side, the time left on the trailing side.
  - **Minimal:** a small ring with the minutes.
  - **Expanded:** label, a large time, pause/resume, +1 min, cancel. A row starts new timers: 1, 5, 10, 25 min, and Custom. Custom is a − / minutes / + stepper (press and hold, or scroll), because the island never takes keyboard focus.
- **Entry points:**
  - Expanded view, a Home quick action, and Timer ▸ in the status menu.
  - `notched://timer?minutes=10&label=Tea` (also `seconds=`), handled in Release builds by a new `URLRouter`. `TimerURL.parse` is pure and tested: 1 s to 24 h, labels capped at 40 characters. If Timers is off, the URL opens its settings.
- **Scenario Lab:** the fake Timer demo is removed. The Lab stays as a DEBUG tool for the other demos, and its full demo starts a real timer when the module is on.

### 6. Shared UI hooks (built on the Mac)

- **`HomeAction`:** modules publish quick actions (symbol, title, on state, a preset menu) for a row on Home. Glass buttons in a `GlassEffectContainer`.
- **`IslandModule.menuItems()`:** optional. The status menu rebuilds them in `menuNeedsUpdate`.

### 7. M2 clean-up

- **Output switching** (`AudioOutputService.select`) runs `AudioObjectSetPropertyData` on a serial utility queue. Bluetooth switches can block for hundreds of milliseconds.
- **The lyric line** stops ticking twice a second. A `TimelineSchedule` yields only the moments the line changes, from the pure `SyncedLyrics.lineChangeDates(after:timeline:)`.

## Permissions

| Module | Permission | Asked when | If denied |
|---|---|---|---|
| Battery, Keep-awake, Timers, Bluetooth | none | — | — |
| Network | Location, for the Wi-Fi name only | the "Show Wi-Fi name" toggle | "Connected"; a fix-it row in the pane |
| Caps Lock | Accessibility, if 27.2 requires it | turning the module on | the module stays quiet; the pane explains why and links to System Settings |

## Testing

- **Pure logic** (`ModuleLifecyclePlan`, `LaunchGuard`, `ModuleDefaults`, `BannerSource`, `BannerQueue`, every reducer, `TimerURL`, `lineChangeDates`) is Foundation-only. The Xcode test target runs it, and it also compiles and passes on Linux with Swift 6.2.
- **`@MainActor` glue** (`ModuleHost`, the coordinator's banner queue) has Xcode tests, run on the Mac.
- **Verification** needs the Mac: screenshots, robustness and performance (the brief's list), measured with `scripts/cpu.sh`.
