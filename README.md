# Notched

A free, open-source "Dynamic Island" for the MacBook notch. It is small, fast and tidy: a pure-black island that merges with the hardware notch (or a Liquid Glass pill on displays without one), and that morphs smoothly to show what's happening on your Mac.

> Status: early development (milestone M1, the shell). See [`docs/ROADMAP.md`](docs/ROADMAP.md).

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
| `scripts/perf.sh [seconds]` | Sample idle CPU and memory of the running app |
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
