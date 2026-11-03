# Contributing to Notched

Notched is a personal project by one student developer, kept small and polished on purpose: quality over quantity. Bug reports, thoughtful ideas and fixes are welcome, but features that add bulk, constant background work or more permission prompts are likely to be declined. Please open an issue before starting anything large.

## Ground rules

- **Read `CLAUDE.md` first.** It is the project brief and the conventions: the module contract, the performance budget, the design rules, the safety rules for risky features, and the licence rules.
- **Event-driven, never polling.** A disabled module must cost nothing. Idle CPU is under 0.5 % with the main modules on, memory under 150 MB.
- **Pure logic goes in a tested reducer.** Anything with a lifecycle gets a `reduce(_:now:) -> [Effect]` with unit tests (see `docs/templates/module-reducer.md`).
- **Non-obvious decisions get a short ADR** in `docs/adr/`.
- **Risky features** (event taps, lock-screen windows, private APIs, process control) follow the safety rules in `CLAUDE.md` and need an ADR first.
- **Swift 6 strict concurrency, SwiftUI, `@Observable`, `os.Logger`** (no `print`). System fonts, SF Symbols, and the Liquid Glass rules in `CLAUDE.md`.

## Licences, important

Notched is GPL-3.0-or-later. Every source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`.

- You may adapt code from GPL-3.0, MIT, Apache-2.0 and BSD projects, with attribution in a comment at the top of the file and an entry in `THIRD_PARTY_NOTICES.md`.
- **Never copy code from** projects with no licence, a non-commercial or Commons Clause licence, AGPL code, or closed-source apps. Reading them for ideas is fine; copying is not.
- Prefer Swift Package Manager dependencies over vendored copies. Vendored code lives in `Vendor/<name>/` with its LICENSE.

## Building and testing

```bash
brew install xcodegen
git clone https://github.com/Notched17/Notched && cd Notched
scripts/go.sh --no-pull      # generate the project, run the tests, install to ~/Applications
```

- The Xcode project is generated from `project.yml`. Never edit `Notched.xcodeproj`.
- Change `DEVELOPMENT_TEAM` in `project.yml` to your own team, and use a stable Apple Development certificate (see ADR-0005) so macOS remembers permissions.
- Run the tests before every commit. All of them must pass.
- Paths contain spaces on the maintainer's machine: quote them in scripts.

## Commits and pull requests

- One logical change per commit, with a message that says why. Reference the roadmap number when there is one, for example `fix(#45): …`.
- Don't commit secrets, `build/` or `DerivedData`.
- For UI changes, include a screenshot, compared with how Apple's own apps look.
- Describe what you ran and saw on a real Mac, not only that it compiles.

## Reporting a bug

Include macOS version, Mac model, whether the display has a notch, which modules are on, and what you expected. Logs help:

```bash
log stream --level debug --predicate 'subsystem BEGINSWITH "me.rkck.Notched"'
```

Please never paste clipboard contents, calendar titles or other personal data.
