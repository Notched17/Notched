# DynamicNotch

A free, open-source "Dynamic Island" for the MacBook notch. It is small, fast and tidy: a pure-black island that merges with the hardware notch (or a Liquid Glass pill on displays without one), and that morphs smoothly to show what's happening on your Mac.

> Status: early development (milestone M1, the shell). See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Requirements

- macOS 26.0 or later (developed on macOS 27.2)
- Xcode 26.3 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple Development signing certificate (a free personal team works). A stable signature means macOS remembers the permissions you grant.

## Build and run

```bash
xcodegen generate                       # creates DynamicNotch.xcodeproj from project.yml
scripts/install.sh                      # builds Debug, installs to ~/Applications, launches
scripts/install.sh Release              # same, Release build
```

Or build by hand:

```bash
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration Debug -derivedDataPath build build
```

Always run the app from `~/Applications/DynamicNotch.app` rather than from `build/`, so macOS ties permission grants to one location.

To use your own signing team, change `DEVELOPMENT_TEAM` in `project.yml` (or override it in an untracked `Configs/Local.xcconfig`).

## Tests

```bash
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -derivedDataPath build test
```

## Project layout

`App/` holds the entry point and app-level controllers. `Sources/` holds the island core, design system, modules, services and the Settings and onboarding UI. `Tests/` holds unit tests for pure logic. `docs/` holds the roadmap, research, architecture decision records (`docs/adr/`) and plans. `CLAUDE.md` describes the conventions.

## Licence

DynamicNotch is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See [`LICENSE`](LICENSE).

Third-party code and ideas used by the project are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
