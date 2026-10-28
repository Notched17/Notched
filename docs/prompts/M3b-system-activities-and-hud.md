We're continuing Notched. M1, M1.5, M2 and M3a are done ✅ (confirm in `docs/ROADMAP.md`; if M3a isn't merged into `main`, stop and tell me). This is **M3b**: the system-level activities (call, screen recording, downloads, camera/mic, Focus, priority) **plus the HUD replacement** (formerly M5). They share the same ingredients: permissions, private-API wrappers, and fail-safes.

**Two parts with a hard checkpoint.** Part A = system activities. Part B = HUD. When Part A is verified and committed, STOP and tell me, so I can end the session and start a fresh one for Part B (the plan, the roadmap and `CLAUDE.md` carry the context). If I say "continue", carry on.

## Model guide (for me, not for you)
Plan mode: Opus high. Build steps: Sonnet. Part B Step B0 (event-tap safety design) and the Screen recording / Focus research spikes: Opus xhigh. Everything else Sonnet or Haiku (via `build-runner`).

## Read first
1. `CLAUDE.md` (binding): especially the safety rules for event taps, private APIs and permissions, and Token economy (use `Explore` and `build-runner`).
2. `docs/ROADMAP.md`: **M3b** section (rows #8, Call, Screen recording, Downloads, #30, #31, and the HUD rows #20, #21, #23).
3. `docs/ISLAND-BEHAVIOR.md` §1, §2, §7. ADR-0006, ADR-0007, the M3a banner-pipeline ADR, the "music stays primary" ADR.
4. `Sources/Modules/` for the reducer convention (every live module has a pure, unit-tested reducer plus a template in `docs/`), `Sources/Services/Audio/` (CoreAudio listeners, reuse them), `Sources/Services/Private/` (where private wrappers live).
5. `docs/research/mac-live-activity-sources.md`.

## Tools
superpowers (brainstorm → plan → TDD → systematic-debugging → verification-before-completion); liquid-glass + hig-* for UI; Xcode MCP (fallback `xcodebuild`); `screencapture`; `scripts/cpu.sh` for performance. Send builds and tests to `build-runner`.

## Step 0: Plan (plan mode)
Propose a plan and wait for approval. Include: for each feature the API route, permission needed and when it's requested (lazily, only when the feature is turned on), its reducer states and tests, failure behaviour ("what the user sees if the API disappears"), and your **questions for me**. Flag every private API explicitly and say how its absence is detected at runtime so the feature hides itself instead of crashing.

## Part A: System activities
Build, test, install, screenshot and commit after each. Each module has its own settings section and on/off toggle, costs nothing when off, and uses a tested reducer.

**A1. Camera / mic in use (#31).**
- CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` and CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`, with property listeners (no polling), debounced 500 ms.
- Compact: orange dot for mic, green dot for camera (as iOS), plus a small glyph. Minimal bubble: just the dot. Expanded: which app is using it where the system tells us (per-process audio input via `kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput` + bundle ID); for the camera, say "An app" if the owner isn't discoverable. Never claim an app name you can't prove.
- Class `live`, not hideable only while the camera is in use (privacy indicator); mic hideable.
**A2. Call (system activity).**
- "In a call" + running duration for known call apps (FaceTime, zoom.us, Microsoft Teams, Slack huddles, Discord, Webex, Google Meet only if the browser is on the list in Settings) using the per-process mic data from A1. Caller name and ringing aren't detectable: don't pretend.
- Class `system`, **not hideable**. Click opens the call app. Add Mute/End only if a public route exists for that app; otherwise omit rather than fake. Call suppresses the plain mic indicator while active (one island item, not two).
- Reducer tests: call start/end with brief mic gaps (grace period 3 s), two call apps at once, mic used by a non-call app (no call), app quit mid-call.
**A3. Screen recording.**
- Spike first (Opus xhigh): what actually signals "screen is being recorded" on macOS 27.2. Candidates: private CGS screen-watcher notifications via a `dlopen` wrapper in `Services/Private/`, plus watching for the `screencapture` process, plus the system recording indicator. Write findings to an ADR. If nothing reliable exists, **stop and ask me** before building a fallback.
- Red dot + elapsed time, with a **Stop** button (end the `screencapture` process or send the system shortcut: whichever is verified to work). Class `system`, not hideable. Hide the module if the symbols aren't found.
**A4. Downloads.**
- FSEvents on `~/Downloads`; recognise in-progress files (`.crdownload`, `.download` bundles, `.part`, `.opdownload`) and the `com.apple.progress.fractionCompleted` xattr. Progress ring in the minimal bubble, bar + filename + speed in expanded, a banner on completion with "Show in Finder".
- Needs Files & Folders (Downloads) permission: request lazily when turned on; show what denial looks like in Settings.
- Reducer tests for multiple simultaneous downloads, renamed-on-finish files, cancelled downloads, and huge numbers of events (coalesce them).
**A5. Focus (#30).**
- Research first and write an ADR: what works on macOS 27.2 (Focus assertions under `~/Library/DoNotDisturb/DB/` needs Full Disk Access; a Focus Filter / App Intents route; distributed notifications). **Ask me before anything that needs Full Disk Access.** If only "a Focus is on" is detectable without FDA, ship that (moon glyph, no name) and make the name an opt-in.
**A6. User-adjustable priority (#8).**
- Settings: reorder activity classes and pin a module above others; feeds `ActivityCoordinator` relevance. System-class items can't be demoted below live. Tests for ordering rules and persistence. (The Layout editor #71 comes later in M4b and will reuse this.)

### Part A verification
- Screenshots in `docs/screenshots/m3b/`: every activity compact, minimal bubble and expanded, on notch and pill; the four-activity case (call + music + download + timer) showing 3 visible and 1 listed.
- Real tests where possible (FaceTime or a Zoom test call, a download, a screen recording). For anything needing me, give me a numbered list and wait.
- Robustness: sleep/wake mid-download and mid-call, enable/disable every module repeatedly with no leaked listeners, deny each permission.
- Performance with everything on: idle < 0.5% CPU, memory < 150 MB; each module's cost reported with `scripts/cpu.sh`.
- Update ROADMAP rows with ✅/🟨 and measurements; ADRs for each private API and permission decision; `THIRD_PARTY_NOTICES.md` if needed.
- Commit, then **STOP (checkpoint)** and give me a short report.

## Part B: HUD replacement (formerly M5)
**B0. Safety design (plan mode, Opus xhigh).** Re-read the event-tap safety rules in `CLAUDE.md`. A bug here can make the keyboard feel broken, so before any code, write a one-page design covering: how the tap is created and re-enabled on `tapDisabledByTimeout`; the rule that **the event is only swallowed if we actually changed the volume/brightness**, otherwise it's passed through; a watchdog that disables the tap after repeated failures; a Settings kill switch plus a menu-bar "Pause HUD" item that works even if the tap misbehaves; tap never installed without Accessibility permission; tests with a fake event source. Wait for my approval.
**B1. Volume HUD (#20).**
- Active `CGEventTap` for system-defined media-key events (volume up/down/mute); set volume via CoreAudio on the default output; show a bar + speaker symbol + output-device icon in the island (reuse the M2 output symbols). Shift+Option = quarter steps.
- On macOS 26+ the system HUD lives in Control Center: **confirm by experiment on 27.2 whether swallowing the key suppresses it**, and record the result in an ADR. If it can't be suppressed, offer "Show alongside the system HUD" or stop and ask me.
- Study dannystewart/volumeHUD (MIT) for the pattern; attribute in `THIRD_PARTY_NOTICES.md` if you adapt code.
**B2. Brightness HUD (#21).** Private DisplayServices via a `dlopen` wrapper in `Services/Private/`; built-in display only; hide the option if symbols aren't found. Same fail-safe rule as B1. Keyboard-backlight keys only if trivial; otherwise skip.
**B3. HUD styles (#23).** Inline-in-notch (default), vertical, circular, minimal. Pure SwiftUI. HUD is a transient banner: pre-empts, then restores; must never steal the primary activity.
**B4. Verify.**
- Hold-to-repeat volume keys, mute, external display (volume works, brightness hidden), AirPods and Bluetooth outputs, switching outputs mid-press, fullscreen apps, and Accessibility permission revoked while running (the tap must stop cleanly and the keys must keep working).
- Screenshots in `docs/screenshots/m3b-hud/`; CPU while repeating keys; no added idle cost.
- ROADMAP, ADRs, report.

## Final report (after Part B)
What was built, screenshots, performance numbers, what works and doesn't on macOS 27.2, decisions you made, anything I need to try myself, and suggestions for M4a.

If any spec turns out impossible or wrong in practice, stop and tell me rather than quietly doing something different. Don't merge or push without asking.
