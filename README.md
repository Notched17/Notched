# Notched

A free, open-source "Dynamic Island" for the MacBook notch. It is small, fast and tidy: a pure-black island that merges with the hardware notch (or a Liquid Glass pill on displays without one), and that morphs smoothly to show what's happening on your Mac.

> Status: a personal project in daily use, built milestone by milestone (M1 to M4b are done; M6 is in progress). Free, open source, GPL-3.0. See [`docs/ROADMAP.md`](docs/ROADMAP.md) for exactly what works and what doesn't.

<!-- Screenshots go here once docs/screenshots/m6/ is filled in. -->

## What it does

Everything is a module you switch on in Settings. A module that needs a permission asks only when you turn it on, and a module that is off costs nothing: no timers, observers or processes.

| | |
|---|---|
| **Now Playing** | Artwork, controls, a visualiser, synced lyrics (opt-in) for Music, Spotify and anything that reports to macOS |
| **Status** | Battery and charging, Bluetooth connections, Caps Lock, network and Wi-Fi, camera and microphone indicators, calls and screen recording, downloads, timers, Keep Awake |
| **HUD** | Volume and brightness shown in the island instead of the big system overlay |
| **Productivity** | Clipboard history (⌃⇧V), calendar countdown with one-click Join, reminders, weather, a colour picker, and a real shell in the island |
| **Developer** | Claude Code usage and approve/deny from the island, and a local Activity API so your own scripts can post to the island |
| **Layout** | Choose what shows beside the notch, the order of the expanded tabs and which ones appear |

The island behaves like the iPhone's: one main activity beside the notch, up to two small bubbles, a short alert expansion when something needs you, and everything else when you open it.

## Permissions

Nothing is asked for at first launch. Each permission is requested when you turn on the module that needs it, and each module works as far as it can without it.

| Permission | Needed by | Why |
|---|---|---|
| Automation (Music, Spotify) | Now Playing | Controls playback and reads what's playing from those apps. macOS asks once per app. |
| Accessibility | HUD | Lets Notched see the volume and brightness keys so it can show its own HUD. If Notched is ever slow to answer, the keys pass straight through to macOS. |
| Calendars (full access) | Calendar | Next event, today's and tomorrow's agenda, meeting links |
| Reminders (full access) | Reminders | Today's and overdue reminders, and ticking them off |
| Location | Network (optional), Weather (optional) | macOS only shows Wi-Fi names to apps allowed to use Location; Weather can use an approximate position instead of a typed city. Both are opt-in. |
| Downloads folder | Downloads | Shows the progress of files being downloaded |
| Bluetooth | Reserved | Not needed today; planned for AirPods battery levels if that experiment works |
| Audio capture | Reserved | Planned for per-app volume if that experiment works |

No permission is needed for: the camera and microphone indicators, Bluetooth device connections, clipboard history (macOS may ask once to allow reading the pasteboard), the colour picker, the terminal, and the Activity API. Notched has no App Sandbox, because the features need things the sandbox forbids, so it is a direct download and not a Mac App Store app.

## Privacy

See [`docs/PRIVACY.md`](docs/PRIVACY.md). In short: nothing is collected or sent anywhere unless you turn on a module that needs the network, and the only ones that do are synced lyrics (LRCLIB), Weather (Open-Meteo) and, if you add them later, updates.

## Known limits

- **No Maps turn-by-turn.** Mac Maps has no live navigation and no API lets another app read an iPhone's Live Activities.
- **No lock-screen widgets yet.** Research is under way (ADR-0031); it will be off by default with several kill switches, or dropped.
- **Per-app volume and AirPods battery are experiments.** They ship only if they prove safe and reliable.
- **Not on the Mac App Store, and not notarised.** You build it yourself (below), signed with your own Apple Development certificate.
- **Built and used on macOS 27.2, Apple Silicon**, with a MacBook Air M4. The target is macOS 26.0 or later. Other Macs and displays have had little testing.
- **Visual polish is still in progress** in several panes and tabs.

## Requirements

- macOS 26.0 or later (developed on macOS 27.2)
- Xcode 26.3 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple Development signing certificate (a free personal team works). A stable signature means macOS remembers the permissions you grant.

## Build and run

```bash
xcodegen generate                       # creates Notched.xcodeproj from project.yml
scripts/install.sh                      # builds Debug, installs to ~/Applications, launches
scripts/install.sh Release              # same, Release build
```

Or build by hand:

```bash
xcodebuild -project Notched.xcodeproj -scheme Notched -configuration Debug -derivedDataPath build build
```

Always run the app from `~/Applications/Notched.app` rather than from `build/`, so macOS ties permission grants to one location.

To use your own signing team, change `DEVELOPMENT_TEAM` in `project.yml` (or override it in an untracked `Configs/Local.xcconfig`).

## Tests

```bash
scripts/test.sh        # regenerates the project, runs the unit tests, prints failures
```

## Development scripts

| Script | What it does |
|---|---|
| `scripts/install.sh [Debug\|Release]` | Build, install to `~/Applications`, relaunch |
| `scripts/test.sh` | Run the unit tests (full log in `build/test.log`) |
| `scripts/go.sh [--no-pull]` | Pull, regenerate the project, run the tests, install and relaunch |
| `scripts/perf.sh [seconds]` | Sample idle CPU and memory of the running app |
| `scripts/perf-table.sh [seconds]` | The per-module CPU and memory table (Debug build) |
| `scripts/soak.sh [hours]` | Overnight sampling of CPU, memory, threads and files into a CSV |
| `swift scripts/window-bounds.swift` | Print the island windows' frames |
| `swift scripts/hit-test.swift x,y …` | Ask the window server which window a click at a point would hit |
| `scripts/settings-shot.sh <pane> <file.png>` | Screenshot a Settings pane |

Debug builds accept `notched://debug/…` URLs so scripts can drive the island, for example `open -g "notched://debug/expand"`. Commands: `expand`, `collapse`, `pill?on=1`, `outline?on=1`, `hello-alert`, `hello-session?on=1`, `theme?notch=liquidGlass&pill=tintedGlass`, `settings?pane=appearance`, `onboarding?step=modules`, `reduce-motion?on=1`, `reduce-transparency?on=1`, `increase-contrast?on=1`, `fullscreen-fallback?on=1`, `appearance?mode=dark`, `launch-at-login?on=1`, `close-windows`. The Scenario Lab (Debug ▸ Scenario Lab in the status menu) drives demo live activities: `lab?demo=timer&do=start` (demos `music`, `timer`, `call`, `agent`, `download`; actions `start`, `end`, `stale`, `hide`, `unhide`, `primary`), `lab?banner=charging`, `lab?alert=timer`, `lab?run=full`, `lab?do=end-all`, `page?id=home` and `setting?multiple=sideBySide`. Release builds ignore them.

Logs: `log stream --level debug --predicate 'subsystem BEGINSWITH "me.rkck.Notched"'`.

## Project layout

`App/` holds the entry point and app-level controllers. `Sources/` holds the island core, design system, modules, services and the Settings and onboarding UI. `Tests/` holds unit tests for pure logic. `docs/` holds the roadmap, research, architecture decision records (`docs/adr/`) and plans. `CLAUDE.md` describes the conventions.

## Licence

Notched is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See [`LICENSE`](LICENSE).

Third-party code and ideas used by the project are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
