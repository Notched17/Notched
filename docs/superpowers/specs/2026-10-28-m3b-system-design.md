# M3b System activities and HUD: design

> **Update after the spikes (28 Oct):** Charlie set aside **Screen recording** (ADR-0014: detection works, Stop doesn't for ⌘⇧5) and dropped **Focus** (ADR-0015: only a per-Focus filter works). Sections S2, S3, A3 and A5, and the `alertsWhenStarted` flag, are kept below for when they return. They are not part of M3b.

## Context

M1–M3a are done and merged (`main` = `abf005e`, PR #2). M3b adds system-level activities: camera/mic in use (#31), Call, Screen recording, Downloads, Focus (#30) and user-adjustable priority (#8). Then, after a **hard checkpoint**, it adds the HUD replacement (#20/#21/#23).

These features all depend on the same three things:
- permissions asked lazily,
- private-API wrappers that hide the feature instead of crashing,
- fail-safes.

Screen recording and Focus have no public API, so each gets a go/no-go spike before any code.

The binding sources are:
- `docs/prompts/M3b-system-activities-and-hud.md`
- `CLAUDE.md`, including the new **model and effort policy**
- the ROADMAP M3b rows
- ISLAND-BEHAVIOR §1/§2/§7
- ADR-0006/0007/0011/0012/0013
- `docs/research/mac-live-activity-sources.md` Q2/Q4/Q5/Q6

### Charlie's decisions (28 Oct)
1. **Focus names** come from an opt-in **Focus Filter** (App Intents). The user picks a name (suggestions: Work, Personal, Sleep, Driving, Fitness, Gaming, Reading, Mindfulness) and a symbol once per Focus. **Never Full Disk Access.**
2. Focus shows a **banner on change**. "Keep showing while on" is a setting, off by default, that adds a passive activity.
3. During a call, the **camera merges into the Call** item, which shows green and orange dots.
4. **The Call has no Mute/End controls.** A click opens the call app.
5. **Priority (#8):** system activities (call, screen recording) are **always first**. The user reorders Now Playing, live (timers, downloads, tools) and passive (status). Pinned modules rank right after system.
6. **On by default:** only Camera & Mic. Calls, Screen Recording, Downloads and Focus are off until turned on.

### Model and effort per step (CLAUDE.md policy: state it in one line before each step; if the session differs, stop and ask)

| Step | Model and effort |
|---|---|
| Session 1: Step 0 housekeeping (two git operations, not worth a switch), **S2 Screen recording spike**, **S3 Focus spike** | **Opus, xhigh** |
| Session 2: A0, S1 + A1, S4 + A4, A3 build (Swift 6 concurrency or private wrappers) | **Sonnet, high** |
| Session 2: A6, A2, A5 build, Part A verification and docs | **Sonnet, medium** |
| Builds, tests, xcodegen, `cpu.sh` / searches | Haiku via `build-runner` / `Explore` (their own frontmatter) |
| Part B: B0 safety design (plan mode) / B1–B3 build | Opus xhigh / Sonnet high |

## Global constraints

- **Licence and logging:** SPDX header on every file. `Log.module("<id>")` / `Log.privateAPI`, never `print`.
- **Concurrency and reducers:**
  - Swift 6 strict concurrency.
  - Every module has a Foundation-only reducer, `mutating func reduce(_:now:) -> [Effect]`. Deadlines are effects, fed back via `OneShotTimer`, and the first observation is silent (`docs/templates/module-reducer.md`).
  - Tests use Swift Testing.
- **Zero cost when off:** after `stop()` there is no listener, stream, subscriber, notify proc, observer or timer. Every new shell joins `Tests/ModuleShellTests.swift` (start/stop ×5 with counters).
- **No polling:** CoreAudio and CMIO listeners, FSEvents, `Progress` subscribers, `NSWorkspace` notifications and KVO, distributed notifications, SkyLight notify procs. Per-second displays use system-ticked `Text(timerInterval:)`. Rings use Core Animation in the render server (ADR-0010).
- **Private APIs** live only in `Sources/Services/Private/`, following the `SkyLightSpaces.swift` pattern (lazy `dlopen`/`dlsym`, `isAvailable`, log once). They are C symbols only, **never Swift-mangled SkyLight symbols**. A missing symbol hides the feature. Each has a DEBUG force-unavailable switch (like `FullscreenMonitor.forceFallback`) to test hiding.
- **Budget** (`scripts/cpu.sh`):
  - idle < 0.5% CPU with all M3b modules on
  - call or recording compact < 1%
  - memory < 150 MB (also reported against CLAUDE.md's 120)
- **Workflow:** builds, tests and `cpu.sh` → `build-runner`. Install with `scripts/install.sh` to `~/Applications`. Screenshot after every UI change.
- **Commits** go on branch `m3b-system`, e.g. `feat(#31): …`, with tests before every commit. **No push or merge without asking.**

---

## Step 0: housekeeping (session 1, before the spikes)

1. Commit Charlie's uncommitted edits on `main` as their own commit (`docs: model and effort policy; prompt updates`): CLAUDE.md, `.claude/agents/*`, `docs/prompts/*`.
2. Create branch `m3b-system`.
3. Save this plan as two files, matching the M3a convention:
   - the design: `docs/superpowers/specs/2026-10-28-m3b-system-design.md`
   - the task list: `docs/superpowers/plans/2026-10-28-m3b-system.md`
4. Commit.

## Spikes (go/no-go before the matching feature)

Probes run **inside the signed, installed app**, so TCC sees Notched and not Terminal. They are DEBUG-only `notched://debug/probe/<name>` handlers that log through `os.Logger`, in `Sources/Debug/Probes/` behind `#if DEBUG`. They're removed when the ADR is written, unless they're worth keeping as diagnostics. **Any stop-and-ask result goes to Charlie before building.**

### S2. Screen recording → ADR-0014 (session 1, Opus xhigh)

Candidates:
- **(a) Private** (`SLSRegisterNotifyProc`, `SLSRemoveNotifyProc`, `SLSIsScreenWatcherPresent`): all exported on 27.2, while the `CGS…` aliases are gone. Notify types 1502/1503 come from community code only. Confirm the callback signature empirically, because `dlsym` succeeding proves nothing about it.
- **(b) Public:** `NSWorkspace.runningApplications` KVO for `com.apple.screencaptureui`, plus a window-list owner/layer check for its menu-bar Stop item. Verify that owner names need no Screen Recording permission.
- **(c) The `screencapture` CLI:** checked only after (a) or (b) fires. macOS gives no launch notification for plain processes, and it is never polled.

Test each against:
- ⌘⇧5 full-screen and area recording
- QuickTime recording
- a ⌘⇧3/⌘⇧4 **still screenshot** (must not count)
- a ScreenCaptureKit app (OBS or CleanShot, if installed)
- FaceTime or Zoom screen sharing

Record the allow-list of sharing apps needed to reject false positives.

**Stop:**
- ⌘⌃Esc via `CGEvent` (needs Accessibility; does it only stop ⌘⇧5 recordings?);
- SIGINT to `screencapture -v` (is the file saved?).
- **Never SIGTERM `screencaptureui`**, because that loses the recording.

Also check:
- whether the existing `hideFromScreenCapture` (`IslandPanel.swift:55`) keeps the island out of ⌘⇧5 recordings on 27.2;
- what the elapsed time can honestly be measured from.

**No reliable route → stop and ask.**

### S3. Focus → ADR-0015 (session 1, Opus xhigh)

1. Whether `_NSDoNotDisturbEnabledNotification`/`Disabled` (undocumented names) fire for **every** Focus on 27.2. They only report changes: there's no starting state, and changes during sleep are missed.
2. `INFocusStatusCenter` with a personal-team signature: the authorization prompt, any capability or Intents extension it needs, and whether `isFocused` is readable at launch and on wake. That would seed state; it must not be polled.
3. Whether a `SetFocusFilterIntent` in the main app (macOS 13+; `static var current` from 13.3):
   - appears under System Settings ▸ Focus ▸ Focus Filters,
   - gets `perform()` on Focus on and off with the user's parameters,
   - works when Notched launches after the Focus turned on.

**No `log stream` fallback, no Full Disk Access. No usable on/off signal → stop and ask.**

### S1. Sensors and call attribution → ADR-0017 (session 2, before A1, Sonnet high)

1. Reading CMIO/CoreAudio device and process properties under Hardened Runtime causes **no TCC prompt and no crash**, without camera/mic usage strings or entitlements. Also measure CMIO's first-call plugin-load cost; it must happen off the main thread.
2. Which process has `kAudioProcessPropertyIsRunningInput = 1` during:
   - FaceTime audio and video calls,
   - a Continuity (iPhone) call,
   - a call in the macOS 26 Phone app,
   - Zoom, Teams, Slack huddles, Discord, Webex,
   - Meet in Chrome and in Safari, as far as they're installed.

   Expect daemons such as `avconferenced` and helpers such as `com.apple.WebKit.GPU`. Record the bundle IDs.
3. **Mute** in each call app for 10 s: does `IsRunningInput` drop? This tests whether the 3 s grace period holds.
4. Whether output-only playback makes the device-level `DeviceIsRunningSomewhere` true on combined devices (USB headset, AirPods in HFP). And which daemons (Siri, speech) appear as input users that macOS's own orange dot doesn't show; they go on a deny-list.
5. Whether `responsibility_get_pid_responsible_for_pid` (libquarantine, **private**, exported here) names Safari for WebKit's GPU process.

### S4. Downloads → ADR-0018 (session 2, before A4, Sonnet high)

- Whether `Progress.addSubscriber(forFileURL: ~/Downloads)` receives Safari, Chrome and Firefox progress on 27.2: fraction, total, throughput, `fileURL`.
- What happens **with the Downloads grant denied** to FSEvents, the subscriber and `getxattr`. If the subscriber works without the grant, some browsers need no permission at all.
- Each browser's partial-file convention:
  - `.crdownload`, including Chrome's `Unconfirmed NNN.crdownload`,
  - the Safari `.download` bundle,
  - Firefox `.part` plus its zero-byte placeholder,
  - `" (1)"` duplicate names,
  - the xattr's locale.

---

## A0. Foundations (Sonnet high; one commit)

### Coordinator fixes (`ActivityCoordinator.swift`), each with a test
- **A non-hideable activity is never left hidden.** `post` clears `isHidden` when `isHideable` is false. Today it keeps the flag (L142–145), so a hidden mic indicator would stay hidden once the camera turns on.
- **A non-hideable activity is never listed-only.** The three visible slots take non-hideable activities first, in rank order, then the rest; primary and bubbles keep rank order. Nothing changes by default: only ScenarioLab posts non-hideable activities today.
- **`LiveActivity.alertsWhenStarted: Bool = true`.** The new-`.system` auto-alert (L150–153) honours it, so Screen recording can avoid expanding into the user's own recording.
- **Ranking moves to a pure `RankingPolicy`** (A6). `ActivityKind` moves into a Foundation-only file and is persisted by **name**.
- **`configuration` `didSet`** refreshes only when it differs from the old value. `AppEnvironment` reassigns it on every settings change.

### Permissions
- **`Permission.downloadsFolder`:**
  - The **probe never touches the filesystem.** It reports the last result written by an off-main read (`Task.detached`; EPERM → `.denied`), persisted. So `refresh()` on the main actor can't block on a TCC prompt, even after `tccutil reset`.
  - `request()` does the first directory read off the main thread, which shows the prompt.
  - Add `NSDownloadsFolderUsageDescription`. The anchor is `Privacy_FilesAndFolders`.
  - Focus permission cases are added only once ADR-0015 says so.

### Banners
- **`TransientBanner.openAction`.** A click during a banner calls it (`IslandController.swift:277` ignores clicks today). The download-complete banner lasts 4 s.

### `SensorUsageService` (`Sources/Services/Sensors/`, in `ModuleServices.sensors`, refcounted like `AudioOutputService`)
- **Threading:** an **actor whose executor is a serial `DispatchSerialQueue`**. CMIO and CoreAudio listener blocks register on that queue (`assumeIsolated`). Bursts coalesce into one rescan. Only value **diffs** go to a `@MainActor @Observable` facade, and nothing blocks main on coreaudiod.
- **Listeners:**
  - CMIO device list, plus `DeviceIsRunningSomewhere` per video device;
  - CoreAudio device list, plus `DeviceIsRunningSomewhere` per input device, as a **trigger** only (it decides by itself only for input-only devices);
  - `ProcessObjectList`, plus per-process `IsRunningInput`, installed **only while some input device runs**. So idle cost is the device listeners alone.
- **Truth:** the mic is in use when a process other than Notched, and not on the deny-list, has `IsRunningInput = 1`.
- **Attribution** is a pure, tested function, cached by pid plus process start time, because pids get reused. Order:
  1. the running app,
  2. a helper inside an `.app` (`proc_pidpath` walked up to the outermost `.app`),
  3. the **private** responsibility pid,
  4. otherwise "An app".
- **Call claims:**
  - Claims are keyed by **attributed app identity**, not pid.
  - The Calls module sets them, and keeps them through the grace period.
  - They are cleared in `CallsModule.stop()`, so a crashed or suspended Calls module can't hide the mic indicator.
  - The indicator reducer receives them as a `.claimsChanged` event.
- **Leak check:** the service exposes `listenerCount` for the leak test.

## A6. User-adjustable priority (#8) (Sonnet medium)

- **`RankingPolicy`** (`Sources/Core/Activities/RankingPolicy.swift`, pure, `Codable`):
  - `order: [ActivityKind]`, covering `media`, `live` and `passive`, with the default `[.media, .live, .passive]` (ADR-0011).
  - `pinned: [ModuleID]`.
  - **The sort key:**
    1. `.system` first, always;
    2. then pinned modules' non-system activities, by pin order;
    3. then the user's class order;
    4. then relevance, then start sequence.
  - `normalized()` drops `.system`, duplicates and unknowns, and adds any missing class in its default slot.
  - **Alerts and swap-clearing stay keyed on kind, not rank.**
- **Coordinator:** `Configuration.ranking`, and an instance-based `ranksHigher`. The default policy leaves every existing test green (`rankByClass`, `twoActivities`, `threeActivities` …).
- **Settings:**
  - `SettingsStore.activityRanking` (key `activities.ranking`, JSON, bad data → default) flows into `activityConfiguration` (`SettingsStore.swift:216`).
  - A "Priority" row in the Modules pane pushes a grouped `Form`:
    - a fixed "Calls & screen recording" row on top;
    - a drag list of "Now Playing", "Timers, downloads & tools" and "Status";
    - a "Pinned" list with an add menu (system modules excluded) and remove;
    - a "Pin Above Others" context item on module rows.
- **Tests:**
  - the default equals ADR-0011;
  - live above media;
  - passive above media;
  - system stays first under any order;
  - a pinned timer beats music but not a call;
  - two pins keep their order;
  - an unknown pin is ignored;
  - bad or old JSON → default;
  - a changed configuration re-ranks;
  - an unchanged one doesn't refresh;
  - a swap works under a custom order.
- **ADR-0016** (coordinator rules and priority): amends ADR-0011 and records the non-hideable rules. It also notes that the ROADMAP says "feeds relevance", but relevance can't express "pinned above" across classes, so the policy changes the comparator instead.

## A1. Camera / mic in use (#31). Module `sensors`, "Camera & Microphone", **on by default** (Sonnet high)

- **Route:** `SensorUsageService` (public CMIO + CoreAudio). **Permission:** none. If S1 finds a prompt → stop and ask.
- **Private:** only the optional responsibility lookup. If it is absent, the attribution falls back.
- **`SensorIndicatorReducer`:**
  - Each sensor has its own phase: `off → pendingOn(since) → on(users) → pendingOff(since)`, with a **500 ms debounce on both edges**.
  - Events: `.snapshot(cameraRunning, micUsers)`, `.claimsChanged(apps, callActive)`, `.tick`, `.wake`.
  - The mic ignores apps a call has claimed, but a **second app using the mic during a call still shows**.
  - The camera is suppressed while a call is active (merged into it), and returns after the call if it's still on.
- **Tests:**
  - a < 500 ms blip shows nothing;
  - a steady signal → shown; an off-blip keeps it showing;
  - `isHideable` is false only while the camera is on;
  - a change of users updates in place with no alert;
  - call claims, including the second-app case;
  - the camera comes back after a call;
  - own pid and deny-listed daemons ignored;
  - the first observation is silent;
  - wake re-seeds without flashing.
- **UI:**
  - Kind `.live`, top relevance within live; the coordinator guarantees it a visible slot.
  - Compact: an orange dot (mic) and/or a green dot (camera), plus `mic.fill`/`video.fill`. Minimal: the dot(s).
  - Expanded: "Microphone: Zoom, Voice Memos" and "Camera: An app". Only proven names are shown; the camera's owner is never claimed.
- **Failure:**
  - A CMIO or CoreAudio error disables that half and logs once.
  - If both halves fail, Settings says "Not available on this Mac".
  - Without the process list, the device-level fallback says "An app".

## A2. Call. Module `calls`, "Calls", off by default (Sonnet medium)

- **Route:** the service's input users matched against a known call-app list. The proposed list is FaceTime and the macOS 26 Phone app, mapping the call daemon from S1 only while one of them is running; Zoom; Teams (new and classic); Slack; Discord; Webex. A browser counts only if ticked in Settings (default none). `NSWorkspace` termination notifications cover app quits.
- **Permission:** none. **Private:** none.
- **`CallReducer`:**
  - One session per app: `pendingStart` (1 s of continuous mic) → `active(startedAt?)` → `grace(+3 s)` → ended.
  - **A call already running when Notched starts shows "In a call" with no duration.** Only a call seen starting gets a timer: never claim what we didn't see.
  - Effects: post/update, end, `.claims(apps)`, `.schedule`.
- **Tests:**
  - a 2.9 s gap keeps the call; 3.1 s ends it;
  - two apps → two activities;
  - a non-call app using the mic → no call;
  - app quit mid-call → ends at once;
  - a browser counts only when ticked;
  - camera on → green dot in the call model;
  - running at launch → no duration;
  - wake mid-call;
  - the claims order between modules.
- **UI:**
  - Kind `.system`, not hideable. It auto-alerts once.
  - Compact: the app icon or `phone.fill` plus the duration (system-ticked), with orange and green dots.
  - Minimal: a green phone. Expanded: the app, the duration, and the mic and camera rows.
  - Click → `NSRunningApplication.activate`.
  - **Performance:** measure a call plus a timer. If it's over 1%, compact shows minutes and seconds appear only when expanded.
- **Failure:** if the process list is unsupported, `isAvailable` is false and the module is hidden in Settings (logged once).

## A3. Screen recording. Module `screenRecording`, off by default. Only after S2 passes (Sonnet high)

- **Route:** S2's choice. The expected route is the **private** wrapper `Services/Private/SkyLightScreenWatcher.swift`, confirmed by the `screencaptureui` checks, plus the sharing-app allow-list.
- **Absence detection:** `dlsym` for the three `SLS…` symbols. If any is nil, `isAvailable` is false, the module is hidden in Settings, and the miss is logged once. `stop()` calls `SLSRemoveNotifyProc`. The callback's context lives for the whole app and is gated by a flag, so a late callback is safe.
- **Permission:**
  - Detection needs none.
  - A ⌘⌃Esc Stop needs Accessibility. It is a sub-toggle, "Show a Stop button", asked for when it's turned on and never mid-recording.
  - Stop shows only when the recorder is confirmed to be ⌘⇧5.
- **`ScreenRecordingReducer`:**
  - `idle → pendingStart(1 s) → recording(since, source) → stopping(3 s timeout)`.
  - It posts with `alertsWhenStarted: false`, so it doesn't expand into the recording.
- **Tests:**
  - a < 1 s watcher (a still screenshot) never shows;
  - start → recording; stop → stopping → idle;
  - the stop timeout;
  - an allow-listed sharing app is ignored;
  - wake re-seed.
- **UI:** kind `.system`, not hideable. A red dot plus the elapsed time from detection, and Stop. Minimal: the red dot.

## A4. Downloads. Module `downloads`, off by default (Sonnet high)

- **Route** (public, per S4):
  - `Progress` file subscription on `~/Downloads`, plus FSEvents on `~/Downloads`.
  - The FSEvents stream runs on its own queue. Its file events are **depth-filtered off the main thread**, and only download-pattern paths reach main. A must-scan or dropped-events flag → one rescan.
  - Progress comes from the subscriber, else from the xattr (locale-tolerant), else from size growth.
  - Progress KVO is coalesced through a `Sendable` sink to ≤ 2 updates a second.
- **Permission:** `.downloadsFolder`, asked when the module is turned on.
  - **Denied** → no stream starts.
  - The settings pane says "Notched can't see your Downloads folder" with **Open System Settings** (screenshot it).
- **`DownloadsReducer`:** one aggregated activity.
  - Pairing:
    - `x.crdownload → x`;
    - the `x.download` bundle → `x`;
    - Firefox `.part` + its placeholder;
    - `" (1)"` duplicates.
  - Completed = the final file has data written after the partial appeared. Cancelled = no fresh final within 2 s, which ends quietly.
  - No change for 60 s → stale. At most 20 tracked.
  - Speed is an EMA that resets across a sleep gap.
  - When the subscriber and FSEvents both report the same file, they merge into one row.
- **Tests:**
  - three at once;
  - each finish convention;
  - Chrome's `Unconfirmed` names;
  - cancelled → no banner;
  - **10 000 events in one batch → one effect set, bounded memory**;
  - comma-decimal xattr;
  - unknown total → indeterminate;
  - two sources, one file;
  - files already partial at start are seeded silently;
  - sleep mid-download.
- **UI:**
  - Kind `.live`, hideable.
  - Minimal: a progress ring, a Core Animation `strokeEnd`. The indeterminate ring also runs in the render server.
  - Compact: an arrow plus %.
  - Expanded: up to 3 rows of bar, name and speed, then "and N more".
  - **Completion banner**: click → reveal in Finder (via `openAction`).

## A5. Focus (#30). Module `focus`, off by default (Sonnet medium)

- **Route:** S3's choice.
  - On/off: distributed notifications and/or `INFocusStatusCenter` to seed state at launch and on wake.
  - **Names:** a `SetFocusFilterIntent` "Show in Notched" with a **name picker** (suggestions plus custom text) and a **symbol picker**. `perform()` feeds the module; `current` seeds it at launch.
- **Absence:**
  - A notification that never arrives can't be detected. With a seed source available, the module cross-checks on start and wake, and logs a mismatch once.
  - The pane shows "Show Focus names" help only if the filter is registered.
- **`FocusReducer`:** `off | on(name?, symbol?)`.
  - Banners go through `BannerSource` (settle 0.5 s, same id restarts).
  - "Keep showing while on" (off) adds a `.passive` activity, posted only once the state is known from a seed.
  - The first observation and wake re-sync are silent.
- **Tests:**
  - on/off banners;
  - rapid toggles → one banner showing the final state;
  - with and without a name;
  - a filter arriving after the notification upgrades the name with no second banner;
  - "keep showing" without a seed posts nothing;
  - wake silent.

---

## Part A verification (Sonnet medium), then STOP: checkpoint

1. **Screenshots** in `docs/screenshots/m3b/`:
   - every activity in compact, minimal and expanded, on the notch and on the pill (`debug.forcePill`, as M3a's pill shots);
   - the **four-activity case**: call + music + download + timer → call primary, 2 bubbles, 1 listed. Use a real call, or the DEBUG Scenario Lab;
   - camera on with music and a call;
   - the Downloads denied state;
   - the Priority pane;
   - the Focus filter in System Settings.
2. **Real tests:** a download in each browser, a ⌘⇧5 recording, Focus toggles. Then **a numbered list for Charlie**:
   - a FaceTime or Zoom test call;
   - a Continuity call;
   - accept and deny the Downloads prompt;
   - set up the Focus filter;
   - ⌘⇧5 Stop.
3. **Robustness:**
   - sleep/wake mid-download and mid-call;
   - every module off and on 10× with no leak (`ModuleShellTests` + `lsof`);
   - deny each permission;
   - the DEBUG force-unavailable switch → the module is hidden;
   - Calls suspended by LaunchGuard → the mic indicator still shows.
4. **Performance:** `scripts/cpu.sh 60 <label>`, idle with everything on, then once per active module, including call + timer.
5. **Docs:**
   - ROADMAP rows ✅/🟨 with measurements;
   - ADR-0014…0018;
   - ISLAND-BEHAVIOR §2/§7 (camera merged into the call, Focus banner + filter, non-hideable rules) and the stale "M5" labels;
   - `THIRD_PARTY_NOTICES.md` only if code was adapted (Atoll and DynamicNotch are read for ideas only).
6. Commit, then **STOP and send Charlie the short report.**

## Part B: HUD (outline; B0 needs its own approval in a fresh session)

- **B0 safety design** (plan mode, Opus xhigh). A one-page design covering:
  - a session tap on system-defined events only;
  - re-enable on `tapDisabledByTimeout`/`ByUserInput`;
  - **swallow only if we changed the value**, passing the event through otherwise. Behaviour at max/min is decided there;
  - a watchdog that removes the tap after repeated failures;
  - a Settings kill switch plus a menu-bar "Pause HUD" item that works without the tap;
  - no tap without Accessibility, re-checked on failure;
  - fake-event-source tests.
- **B1 volume (#20):**
  - `NX_SYSDEFINED` subtype 8, keys `SOUND_UP/DOWN/MUTE`.
  - CoreAudio virtual main volume and mute on the default output; ⇧⌥ gives quarter steps.
  - The HUD reuses `AudioOutputDevice.symbol`. Accessibility is asked when the HUD is turned on.
  - **27.2 experiment:** does swallowing suppress the Control Center HUD? Write an ADR; if not, offer "alongside" or ask.
  - dannystewart/volumeHUD (MIT) is the pattern; attribute it if adapted.
- **B2 brightness (#21):**
  - **Private** DisplayServices `Get`/`SetBrightness`/`CanChangeBrightness` (exported on this Mac) via `Services/Private/DisplayServicesBrightness.swift`.
  - Built-in display only. The option is hidden if `dlsym` fails or the display can't change.
- **B3 styles (#23):** inline (default), vertical, circular, minimal. The HUD is a `TransientBanner` with its own policy (same id restarts, no rate limit); it never takes the primary.
- **B4 verify:** per the prompt. Screenshots go in `docs/screenshots/m3b-hud/`.

## Questions that come up only after the spikes

- **S2:** if recording can't be told apart from ScreenCaptureKit and sharing apps, should it say "Screen being captured", or cover ⌘⇧5 and QuickTime only?
- **S1:** if a call app drops the mic when muted, should that app get a longer grace than 3 s? Slack voice clips will look like calls; is that acceptable?
- **B0:** at max/min volume, should the key be swallowed and our HUD show "max", or passed to macOS? **Answered 29 Oct: swallowed, and our HUD shows full or empty** (`2026-10-29-m3b-hud-tap-safety-design.md`).

## Verification (end to end, per feature)

`build-runner` → `scripts/test.sh` (all suites, including the new reducer, ranking, attribution and shell-leak tests) → `scripts/install.sh Debug` → trigger the real event → `screencapture -x -R<island rect>` and review it against Apple's Dynamic Island → `scripts/cpu.sh` → commit.

At the end of Part A: the checklist above, then the checkpoint report.
