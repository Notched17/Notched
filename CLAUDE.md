# Notched: project brief for Claude Code

A personal, free and open-source (GPL-3.0) macOS "Dynamic Island" for the MacBook notch. It is built by one student developer (Charlie) for daily use, with optional donations later. **Quality over quantity.** The research shows users love the focused, polished apps (Alcove, MediaMate) and complain about the bloated ones (Droppy, Atoll, Notchy): high idle CPU, constant permission prompts and regressions. This app must feel like Apple shipped it.

`docs/research/notch-app-research.md` is the full competitor and API research, with numbered features (#1–#77). `docs/ROADMAP.md` lists the milestones and the spec for every chosen feature. Read the relevant ROADMAP section before starting any milestone.

## Environment

- Dev machine: macOS 27.2 "Golden Gate", latest Xcode. The machine may or may not have a notch, so detect it and support both.
- **Deployment target: macOS 26.0.** That lets us use the native Liquid Glass APIs with no back-ports.
- The project folder path contains a space (`.../Personal Projects/Notched`). Always quote paths in shell commands.
- The project is generated with **XcodeGen** from `project.yml`. Never hand-edit `.xcodeproj`. Change `project.yml` and run `xcodegen generate`.
- Build from the CLI:
  `xcodebuild -project Notched.xcodeproj -scheme Notched -configuration Debug -derivedDataPath build build`
  Use the Xcode MCP server (`xcode`) if it is connected.
- Bundle ID prefix: `me.rkck`. Main app: `me.rkck.Notched`.
- Signing: use a stable **Apple Development** certificate (a free personal team works), not ad-hoc. Ad-hoc signatures change on every build, so macOS forgets the Accessibility, Input Monitoring and Screen Recording grants each time. Always run the app from a stable install location (copy it to `~/Applications/Notched.app` before launching) for the same reason.
- No App Sandbox. Hardened Runtime on. Key features need private frameworks, Accessibility and `/usr/bin/perl` (mediaremote-adapter), so this is a direct-download app, never Mac App Store.

## Licence rules (important)

The app is **GPL-3.0**. Every source file starts with an SPDX header: `// SPDX-License-Identifier: GPL-3.0-or-later`.

- **May copy or adapt, with attribution in `THIRD_PARTY_NOTICES.md` and a comment at the top of the file:**
  - GPL-3.0: TheBoredTeam/boring.notch, Ebullioscopic/Atoll, monuk7735/mew-notch.
  - MIT, Apache-2.0 and BSD: MrKai77/DynamicNotchKit, Lakr233/NotchDrop, Lakr233/NotchNotification, Lakr233/SkyLightWindow, ungive/mediaremote-adapter (BSD-3), dannystewart/volumeHUD, exelban/Stats, farouqaldori/vibe-notch (Apache-2.0), migueldeicaza/SwiftTerm, sindresorhus/KeyboardShortcuts, sparkle-project/Sparkle.
- **Never copy code from** shobhit99/SuperIsland (no licence means all rights reserved), Droppy (Commons Clause), lihaoyun6/AirBattery (AGPL; reading it for ideas is fine), or any closed-source app (Alcove, MediaMate, Notchy, NotchNook).
- Prefer Swift Package Manager dependencies over vendored copies. If you vendor code, put it in `Vendor/<name>/` with its LICENSE file.

## Architecture

```
App/                 entry point, AppDelegate, Info.plist, entitlements
Sources/
  Core/
    Island/          NSPanel host, NotchGeometry, per-screen IslandController, hit-testing/click-through
    Activities/      ActivityCoordinator (ranking, primary + minimal, alerts, banners), LiveActivity + presentation regions
    Modules/         IslandModule protocol, ModuleRegistry
    Scheduling/      RefreshScheduler (single timer source, power-aware, pauses when hidden or asleep)
    Permissions/     PermissionCenter (status + request + deep-link to System Settings for each TCC permission)
    Settings/        SettingsStore (@Observable, UserDefaults-backed, typed keys)
  DesignSystem/      tokens (spacing, radii, springs), glass components, IslandShape, SF Symbol helpers
  Modules/<Name>/    one folder per feature: <Name>Module.swift, <Name>Model.swift, Compact/Expanded views, <Name>Settings.swift
  Services/          system integrations shared by modules (NowPlaying, Audio, Power, Bluetooth, Network, Calendar...)
  SettingsUI/        the Settings window (sidebar + panes, macOS 26 style)
  Onboarding/        first-run flow and permission walkthrough
Vendor/              vendored third-party code with licences
Tests/               unit tests for pure logic
docs/                research, roadmap, prompts, ADRs
```

**Module contract.** Every feature is an `IslandModule`:
- `id`, a display name and an SF Symbol.
- `isEnabled`. Settings toggle it (#70). Everything except the core shell is **off by default** or asks on first use.
- The permissions it requires. They are only requested when the user enables the module.
- `start()` and `stop()` lifecycle. A disabled module must cost zero CPU: no timers, observers or processes.
- It publishes `LiveActivity` values (kind, relevance, regions for compact leading/trailing, minimal and expanded, optional stale date and alert) and `TransientBanner`s to the `ActivityCoordinator` through its scoped `ActivitySink`.
- It may provide a full expanded "tab" view and a settings pane.

**ActivityCoordinator (#8)** decides what the island shows, like the iPhone Dynamic Island (`docs/ISLAND-BEHAVIOR.md`, ADR-0006):
- Ranking: kind (system > live > media > passive), then relevance, then start order.
- One primary activity owns both compact sides; up to two more show as minimal bubbles; the rest are listed in the expanded view.
- Users can swap the primary, and hide activities (except non-hideable system ones).
- Activities go stale and end; ended ones stay under Recent for a while.
- Alerting updates expand the island briefly, one at a time, never interrupting the user. Short system events use transient banners.
- The island owns layout and animation: modules fill named regions only.
- Unit-test this logic.

**Event-driven, not polling.** Use system notifications, KVO, CoreAudio property listeners, IOKit notifications, `NWPathMonitor`, EventKit change notifications and `DistributedNotificationCenter`. Where polling is unavoidable, register with `RefreshScheduler`. It coalesces timers (tolerance ≥ 10%), runs slower on battery or Low Power Mode, and pauses while the screen is locked or asleep, or when the relevant UI is hidden.

**Performance budget** (check with `top -pid` or Activity Monitor before finishing any milestone):
- Idle CPU < 0.5% with all M1–M3 modules on.
- Memory < 120 MB.
- No main-thread work longer than 16 ms during animations.

## Design: "as if Apple designed it"

**Design tooling.** Read these before writing UI:
- The installed `swiftui-liquid-glass` and `hig-*` skills (see `docs/SETUP.md`).
- Apple's Liquid Glass docs that ship inside Xcode. Search with `find /Applications/Xcode*.app -type d -name AdditionalDocumentation`. Use any Liquid Glass or SwiftUI guides there as the source of truth over memory.

**The island itself:**
- On a notched display, the compact island is **pure black** so it merges with the hardware notch, like iPhone's Dynamic Island. Its width and height come from `NotchGeometry`, and its corners use the continuous squircle shape (`RoundedRectangle(style: .continuous)` or a custom notch shape with concave top shoulders).
- On non-notch displays it is a floating pill just below the menu bar. Its default theme is Liquid Glass (`.glassEffect(.regular, in: .capsule)`), with a "black" option.
- Expanding morphs one continuous shape: animate size and corner radius, never cross-fade between two windows. Use `@Namespace` with `matchedGeometryEffect` (or `glassEffectID` inside a `GlassEffectContainer` for glass elements) so content morphs between compact and expanded.
- Motion: springs everywhere. Store them as tokens, e.g. expand `.spring(response: 0.42, dampingFraction: 0.78)`, collapse slightly faster and less bouncy, and a tiny bounce on new alerts. Tune them by eye. Keep content transitions short (`.blurReplace`, `.opacity` combined with `.scale(0.9)`).
- Respect **Reduce Motion** (swap springs for quick fades), **Reduce Transparency** (no glass, use solid materials) and **Increase Contrast**.

**Liquid Glass usage:**
- Use it for controls floating over content: playback buttons, chips and toggles.
- Use `.buttonStyle(.glass)` and `.glassProminent`, and `Glass.regular.tint(...).interactive()` for touch-like feedback.
- Group neighbouring glass views in a `GlassEffectContainer(spacing:)` so they blend and morph.
- Never stack glass on glass. Never apply glass before layout modifiers.

**Visual details:**
- Typography: system fonts only (SF Pro and SF Pro Rounded for numerals in the island), Dynamic Type-friendly sizes, and `.monospacedDigit()` for anything that ticks.
- Icons: SF Symbols only, with symbol effects (`.symbolEffect(.bounce)`, `.contentTransition(.symbolEffect(.replace))`) for state changes. Use hierarchical or palette rendering.
- Colour: monochrome white on black in the notch. Album-art accent colours may tint the media UI subtly. System accent colour elsewhere.
- Haptics: `NSHapticFeedbackManager` `.alignment` / `.levelChange` on snapping and gesture thresholds (trackpad only).

**Settings window:** a standard macOS 26 settings window, with a `NavigationSplitView` sidebar of panes (General, Appearance, Modules, Permissions, About). It uses native `Form` with `.formStyle(.grouped)`, matching System Settings. Keep it clean: no custom chrome.

**Verify visually.** After any UI change, build, launch and take a screenshot. For the top-centre island region:
`screencapture -x -R<x>,<y>,<w>,<h> /tmp/island.png`
For the whole screen: `screencapture -x /tmp/screen.png`. Look at the image before calling the work done, and compare it against Apple's own Dynamic Island and the Tahoe or Golden Gate system UI.

## Conventions

- **Language and frameworks:**
  - Swift 6 language mode with strict concurrency done properly. UI and models are `@MainActor`. Services use actors or `Sendable` types.
  - Use `@Observable`, not `ObservableObject`.
  - SwiftUI for all views. AppKit only where needed (NSPanel, event taps, NSPasteboard, NSColorSampler, status item).
- **Private APIs:** load them only through small wrappers in `Services/Private/` with `dlopen` and `dlsym`. Every wrapper fails gracefully: the feature hides itself and logs once. Never crash.
- **Logging:** `os.Logger` with a subsystem per module. No `print`.
- **Tests:** XCTest or Swift Testing for pure logic:
  - Notch geometry
  - ActivityCoordinator
  - LRC lyric parser
  - Claude usage log parser
  - Clipboard dedupe

  Run the tests before every commit.
- **Git:**
  - Commit after each completed feature, with clear messages that reference feature numbers, e.g. `feat(#9): now playing compact + expanded views`.
  - Never commit secrets, `build/` or `DerivedData`.
- **Decisions:** when you make a non-obvious architectural decision, add a short ADR in `docs/adr/`.
- **Asking:** if a requirement is ambiguous or a feature turns out to be impossible on macOS 27, stop and ask Charlie rather than inventing behaviour.

## Safety rules for risky features

- **Event taps (HUD replacement, #20/#21):**
  - Always pass events through if the app's handler is slow or the change fails (volumeHUD's pattern).
  - Re-enable the tap after `kCGEventTapDisabledByTimeout`.
  - Add a menu-bar "Disable HUD replacement" escape hatch.
- **Lock-screen windows (#59):** one developer locked himself out of his Mac four times building this.
  - Gate it behind a setting that is off by default.
  - Never take keyboard focus on the lock screen.
  - Never cover the password field or the user picker.
  - Test with the feature set to auto-disable after a crash, i.e. if the last session didn't exit cleanly.
- **The app is a menu-bar agent (`LSUIElement`).** The status item must always offer: Settings, Pause island, Quit.

## Token economy (delegation)
- Delegate file searches, "where is X" lookups, and summarising to the `Explore` subagent (runs on Haiku).
- Delegate every `xcodebuild`, test, `xcodegen` and perf-script run to `build-runner` (Haiku). It returns pass/fail plus only the failing lines.
- Keep planning, design decisions, Swift 6 concurrency work, all code edits, debugging and screenshot critique on the main model. Do not hand these to Haiku.
- Read only the file ranges you need. Don't re-read files you just edited.
