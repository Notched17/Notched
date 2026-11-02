# M6 plan: the hard parts, then release readiness

- Status: **approved 2 Nov 2026; Charlie's answers are in §10**
- Date: 2026-11-02
- Prompt: `docs/prompts/M6-hard-parts-and-release.md`
- Starting point: `main` at 5aa904b (M4b merged, PR #11)

## 0. Ground rules for this milestone

- **Every hard item has a gate.** Spike → measured results → ADR with a go/no-go → Charlie approves → build. A no-go stops that item; it's dropped from the roadmap (✖, with the reason) rather than shipped fragile.
- **The spikes need the Mac.** These cloud sessions are Linux with no Xcode or Swift. I write the spike code and a numbered test sheet; Charlie runs it; the results come back as a file; I make the call from the numbers. To keep round trips down, the 6.1 and 6.2 spikes go out together in one build.
- **Spikes run inside the signed, installed app**, not as command-line tools, so macOS asks for and records *Notched's* permissions (the M3b probe pattern, `Sources/Debug/Probes/`). They're `#if DEBUG`, started from `notched://debug/probe?name=…` (also added to the Debug menu), and log to `me.rkck.Notched.probe`. Each probe also writes a plain-text results file, `~/Library/Logs/Notched/spike-<name>.txt`, which Charlie sends back or commits to `docs/spikes/`. Probes are deleted once their ADR is written.
- **Model switches** follow the prompt's guide (table in §8). I stop and say so before each switch.

## 1. Housekeeping first (small, before the spikes)

- ROADMAP: mark the M4a rows (#62, #63, Activity API) and the M4a status line ✅ **if Charlie confirms they're working** (Q1).
- Carry-overs from M4b go into 6.5, not here: screenshots, per-module CPU, the listed-only-alert question, clipboard image encoding off the main thread, ⌘⇧V.

## 2. 6.1 Spike: per-app volume mixer (#17)

### How it would work
macOS 14.4+ Core Audio **process taps**: `AudioHardwareCreateProcessTap` with a `CATapDescription` for one process, `muteBehavior = .mutedWhenTapped`, so the app's own output is silenced while tapped; a **private aggregate device** holding the tap plus the current output device; an IOProc on the aggregate that copies the tapped audio to the output at the chosen gain. Apps that play through helper processes (Safari and Chrome play from a WebContent or GPU helper) are mapped to their app with the existing `ResponsibleProcess` wrapper.

**Key design principle if it's a go:** an app is tapped **only while its slider is below 100 %**. At 100 % nothing is created, so the default costs zero CPU, adds no latency and needs no permission until the user first moves a slider.

### The spike (`AudioTapProbe`, debug only)
1. **List** apps producing audio now: `kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyIsRunningOutput`, PID, bundle id, responsible app. Event-driven via property listeners (no polling).
2. **Attenuate one app** to 30 % while another plays untouched.
3. **Record the permission prompt exactly** (wording, which System Settings pane, what happens on deny).
4. **Measure:** CPU of Notched (with `scripts/cpu.sh`) for 0, 1 and 3 tapped apps; the latency Core Audio reports for the aggregate (device and stream latency, safety offset, buffer size), and a by-ear lip-sync check with a video.

### Test sheet for Charlie (numbered, about 20 minutes)
Music in Music.app and a YouTube video in Safari playing together, then: tap Music at 30 % · drag 30→100→0 % · quit Music while tapped · switch output built-in ↔ AirPods while tapped · a sample-rate change (Audio MIDI Setup) · sleep/wake · **`kill -9` Notched while an app is tapped (its audio must come back by itself)** · two apps tapped at once · listen for clicks or dropouts in the untapped app throughout.

### Go/no-go criteria (written before the results come in)
| Must hold for a **go** | Measured how |
|---|---|
| Audio comes back on its own if Notched crashes or is killed while tapping | `kill -9` step. **If an app stays muted: no-go, no exceptions.** |
| No audible glitch in untapped apps | listening, every step |
| Added latency ≤ ~30 ms on built-in speakers; lip-sync acceptable on AirPods | reported latency + video check |
| CPU ≤ 0.5 % per tapped app while playing; 0 % with no taps | `scripts/cpu.sh` |
| Recovers from an output-device change or the app quitting within ~1 s, without the user doing anything | test sheet |
| One understandable permission prompt, asked only when a slider is first moved | prompt record |

### If go
An **Audio** tab: a slider per app playing (icon, name, mute), the M2 output switcher at the top, and room for the AirPods row (6.2). A pure `MixerReducer` (apps appear and disappear, slider changes, device changes, tap failures → back off and show "Can't control this app"). `Services/Audio/ProcessTapEngine` owns taps and aggregates on a real-time-safe path (no allocation or locks in the IOProc; gain passed atomically). The Audio tab is a fifth tab candidate; the layout editor lets the user choose. ADR-0029.

### If no-go
Stop and tell Charlie; #17 → ✖ with the evidence.

## 3. 6.2 Spike: AirPods and accessory battery (#28)

Three routes, all **original code** (never AirBattery):

| Route | What | Permission | Cost |
|---|---|---|---|
| A. Private IOBluetooth | `IOBluetoothDevice` battery properties (left, right, case, single) read through a `Services/Private/` `dlopen`/KVC wrapper that fails gracefully | probably Bluetooth (spike records it) | one read on connect |
| B. BLE advertisements | CoreBluetooth scan for Apple's proximity-pairing manufacturer data, decoding left/right/case battery and charging flags from the publicly documented format | Bluetooth (already in Info.plist) | scan only for a few seconds after an AirPods connect, never continuously |
| C. `system_profiler SPBluetoothDataType -json` | Apple's own report, which lists AirPods battery levels | none expected | one process, ~0.5 s, on connect only |

**Spike (`AccessoryBatteryProbe`):** with Charlie's AirPods connected, in the case, one bud out, charging, and after a reconnect, each route logs exactly what it returns and how long it took. Results go into a table in ADR-0030.

**Go if** at least one route gives left/right/case values that match what the Bluetooth menu shows, within 5 %, within 3 s of connecting, on every test. Prefer the route with no new permission (C or A) and use B only if those fail. **If go:** left/right/case battery in the M3a Bluetooth connect banner and in the Audio tab (or in the Bluetooth banner only, if 6.1 is a no-go), hidden automatically when no route works. Otherwise #28 → ✖.

## 4. 6.3 Lock-screen widgets (#59) and lyrics (#13b)

This is the riskiest item: it can lock Charlie out of his Mac. It runs in three gated stages.

**Stage 1: safety design (Opus xhigh, needs Charlie's approval before any lock-screen code).** ADR-0031 will set out, at minimum:
- **Off by default**, behind a toggle with a clear warning. A **kill switch** in Settings and in the status menu, and a launch argument `--no-lock-screen` that disables it before anything starts.
- **Windows exist only while locked:** created on `com.apple.screenIsLocked`, destroyed on `com.apple.screenIsUnlocked`. Also destroyed on a session switch (`NSWorkspace.sessionDidResignActive`), screen sleep and a display change. A watchdog removes them if an unlock is missed.
- **Never takes keyboard focus** (`canBecomeKey` false, non-activating) and **never covers the password field or the user picker.** Widgets go in a fixed safe zone, worked out from Charlie's photos of the macOS 27 lock screen (Q6).
- **Crash rules:** if the last session didn't quit cleanly (`LaunchGuard`), the feature turns itself off until the user turns it back on. A crash while locked must leave the lock screen working: verified with a timed `kill -9`.
- **Nothing sensitive unless chosen:** the next event shows as "Event in 12 min" unless "Show event titles" is on. Artwork and lyrics only if their own switches are on.
- **Private API** through a small `Services/Private/SkyLightLockScreen` wrapper adapted from Lakr233/SkyLightWindow (MIT, attributed), with `dlopen`/`dlsym`. Any missing symbol hides the feature and logs once.

**Stage 2: spike.** A plain label on the lock screen that **destroys itself after 60 s** whatever happens. Test sheet: lock/unlock 20×, wrong password, fast user switching, display sleep, external display, `kill -9` while locked, and is the password field still usable each time? Go/no-go in ADR-0031.

**Stage 3: build (if go).** Now Playing (artwork, play/pause/skip), battery, next event. Then #13b: the current lyric line under the player, reusing `LyricLineSchedule`. Physical test sheet as numbered steps.

## 5. 6.4 Auto-updates (#76): Charlie decides (Q2)

If yes: Sparkle 2 (SPM), EdDSA appcast on GitHub Pages, stable and beta channels, **never installs without consent**, private key in the Keychain and documented in `docs/RELEASING.md`, never committed. If no: the row is marked ⏸ parked.

## 6. 6.5 Release readiness (always)

1. **Accessibility and HIG audit** with the `hig-compliance-auditor` skill: VoiceOver labels, keyboard navigation, Reduce Motion, Reduce Transparency, Increase Contrast. Fix the findings; Charlie spot-checks with VoiceOver.
2. **Onboarding** reviewed end to end as a brand-new user: every permission explained and optional.
3. **The M4b carry-overs:** clipboard image encoding off the main thread; the ⌘⇧V and listed-only-alert decisions (Q7); M4b and M6 screenshots.
4. **Robustness:** crash-loop and safe mode exercised, every module toggled repeatedly, no leaked listeners, assertions, timers or processes after 30 minutes of mixed use; then **Charlie leaves it running overnight** and `scripts/cpu.sh` plus a footprint reading are taken after 8 hours. I'll add a `scripts/soak.sh` that samples CPU and memory every 10 minutes into a CSV, so the overnight run needs no attention.
5. **Performance table:** one row per module, idle and active, from `scripts/cpu.sh`, run by Charlie with a script that walks through the modules.
6. **Repo and docs:** README (what it is, screenshots, features, a permissions table with the reason for each, build steps, known limits such as no Maps turn-by-turn), CONTRIBUTING, LICENSE (already GPL-3.0; checked), a full `THIRD_PARTY_NOTICES.md` audit, `docs/PRIVACY.md` (what touches the network: lyrics, weather, updates if chosen; what never leaves the Mac), and a donations placeholder if wanted (Q3). The Info.plist audio-capture string will be corrected: it currently mentions a visualiser that doesn't capture audio.
7. **Signing and notarisation** (Q4): `docs/RELEASING.md` and `scripts/release.sh` (archive, Developer ID sign, notarise with `notarytool`, staple, zip or DMG). Nothing that publishes runs without Charlie's say-so.
8. **ROADMAP** marked honestly ✅/🟨/✖. Parked stays parked: #54, #61, Spotify likes.
9. **Final fresh-reviewer pass** on the whole M6 branch (Opus high); critical and important findings fixed.

## 7. Order and round trips

1. Housekeeping (§1).
2. **Spike build 1:** 6.1 + 6.2 probes in one build. Charlie runs both test sheets in one sitting.
3. ADR-0029 and ADR-0030 with go/no-go → Charlie approves.
4. **6.3 Stage 1** safety design → Charlie approves. *This can be reviewed while I build 6.1/6.2.*
5. Build 6.1 and 6.2 (whichever are go), and in the same Mac round, the 6.3 Stage 2 spike.
6. 6.3 Stage 3 build (if go), with its physical test sheet.
7. 6.4 (if wanted), then 6.5, then the overnight soak, the final review, the final report.

## 8. Model and effort for each step

| Step | Model and effort |
|---|---|
| Step 0: this plan | Opus, high |
| §1 housekeeping (ROADMAP) | Sonnet, medium |
| 6.1 and 6.2 spike code, test sheets, go/no-go ADRs | **Opus, xhigh** |
| 6.3 Stage 1 safety design and Stage 2 spike + go/no-go | **Opus, xhigh** |
| Building 6.1–6.3 after approval | Sonnet, high |
| 6.4, the 6.5 build work, polish, README, docs, ROADMAP | Sonnet, medium |
| Repo mechanics, builds, tests | Haiku (`build-runner`), on the Mac |
| Final fresh-reviewer pass | Opus, high |

## 9. Questions for Charlie

1. **M4a:** are the Claude Code usage tab, the hook status/approve flow and the Activity API working for you, so I can mark them ✅?
2. **Auto-updates (6.4):** do you want them at all? If so, set up the Sparkle keys now, or later when you share the app?
3. **Donations:** a placeholder link in the README and the About pane? If so, which service (GitHub Sponsors, Ko-fi, Buy Me a Coffee), or a placeholder for now?
4. **Signing:** do you have (or plan to get) a **paid** Apple Developer Program membership? Developer ID signing and notarisation need it; with only the free team, `RELEASING.md` will describe local builds only.
5. **AirPods:** which model (AirPods Pro 2, AirPods 4, Max…)? Any other Bluetooth headphones I should try?
6. **Lock screen:** could you send two photos of the macOS 27 lock screen, one with music playing and one without? I need to see where the clock, password field and Apple's own Now Playing control sit, both to choose a safe zone and to check that our widget wouldn't just duplicate Apple's.
7. **M4b carry-overs:** (a) keep ⌘⇧V as the clipboard hotkey, or default to something that doesn't override Paste and Match Style (e.g. ⌥⌘V)? (b) Should a module turned off in *Show in Compact* still be allowed to alert?
8. **Mac with a notch?** Which MacBook is this (for the lock-screen layout and the performance table)?
9. **Working loop:** OK with me sending spike builds plus numbered test sheets, and you sending back the results files? (The alternative is running M6 in a local Claude Code session on the Mac, which can build and read logs directly. That's faster for the spikes.)

## 10. Charlie's answers (2 Nov 2026) and what changes

1. **M4a:** the usage tab's token counts and graph work; **the cost estimate doesn't**. The Activity API hasn't been checked. → #62 stays 🟨 until the cost estimate is fixed (housekeeping step, Sonnet medium). The spike test sheet gets a short Activity API check (a `notched://banner` link and a `curl` call), so #63 and the API can be marked from real results.
2. **Auto-updates:** wanted, but set up later. → 6.4 is not done in M6; #76 is marked ⏸ "later, wanted".
3. **Donations:** later. → no placeholder in M6.
4. **Signing:** local builds only for this project. → `docs/RELEASING.md` describes a local Release build and install (Apple Development signing, as ADR-0005); no Developer ID or notarisation script.
5. **AirPods:** test other models only if needed. → the spike records whatever model Charlie's AirPods report; the decoder handles the documented model ids, and other models are a later check if the route depends on the model.
6. **Lock screen:** macOS 27's standard lock screen shows nothing for media, so our widget doesn't duplicate Apple's. The safe zone is still designed in Stage 1; the Stage 2 test sheet asks for one photo with the test label showing, to confirm it.
7. **(a)** The clipboard hotkey becomes **⌥⇧V** (KeyboardShortcuts saves the old default on first launch, so a one-time migration moves an untouched ⌘⇧V to ⌥⇧V). **(b)** A module turned off in *Show in Compact* **doesn't alert** either; ADR-0028 is updated. Both in the housekeeping step.
8. **Mac:** MacBook Air M4 15-inch (notched display), the reference machine for the performance table.
9. **Working loop:** spike builds, numbered test sheets, results files back.

### Revised order
1. **Now (Opus xhigh):** the 6.1 and 6.2 spike probes and their test sheet (`docs/spikes/M6-spike-1.md`).
2. **Housekeeping (Sonnet medium):** the cost estimate, ⌥⇧V, the listed-only alert rule, ROADMAP. It lands in the same build as the probes, so Charlie runs one build.
3. Charlie runs the test sheet; then (Opus xhigh) ADR-0029/0030 go/no-go and the 6.3 Stage 1 safety design.

### Progress (2 Nov 2026)
- Spike build 1 compiles; all 1,128 tests pass on the Mac. Charlie runs `docs/spikes/M6-spike-1.md` later.
- **6.3 Stage 1 written:** ADR-0031 (proposed). SkyLightWindow's technique is adapted into our own checked wrapper rather than used as a package: its window is full-screen and key, its level-400 Space stays shown after unlock, and its `dlsym` results aren't checked. A passive `lockevents` probe (no windows) is added to the spike sheet as §4, to confirm the lock signals the design relies on.
- **ADR-0031 approved** with Charlie's changes: switches for other displays and for Macs with other user accounts, both off by default.
- **6.3 Stage 2 written:** `SkyLightLockScreen` (checked wrapper), `LockScreenReducer` + geometry + kill switch + account filter (pure, tested in `Tests/LockScreenTests.swift`), `LockScreenController` (the shell, reused in Stage 3) and the `lockscreen` probe (a grey label that removes itself after 60 s). Spike sheet §5 is the physical test list. SkyLightWindow attributed in `THIRD_PARTY_NOTICES.md`.

### Progress, 6.5 (2 Nov 2026, Sonnet)
Done without the Mac: clipboard image encoding off the main thread; `scripts/soak.sh`, `scripts/perf-table.sh`; README, `docs/PRIVACY.md`, `CONTRIBUTING.md`, `docs/RELEASING.md` (local builds only); notices audit; accessibility audit and fixes (`docs/ACCESSIBILITY.md`: an Open Island route for keyboard and VoiceOver users, Reduce Motion, contrast, click targets); onboarding wording. Needs the Mac: VoiceOver spot-check, performance table, 8-hour soak, screenshots. Needs spike results: #17, #28, #59.
