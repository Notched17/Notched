You're building **DynamicNotch**, my personal, free, open-source (GPL-3.0) macOS "Dynamic Island" for the MacBook notch. I'm a Swift/SwiftUI student developer on macOS 27.2 "Golden Gate" with the latest Xcode. I want this to look and feel like Apple designed it: native Liquid Glass, perfect spring animations, zero jank, and a negligible battery cost.

## Read first (in this order)
1. `CLAUDE.md`: environment, licence rules, architecture, the design language and safety rules. Treat it as binding.
2. `docs/ROADMAP.md`: milestones and per-feature specs. **This session covers M1 only.**
3. `docs/research/notch-app-research.md`: competitor and API research. Skim the summary, section A of the checklist, and "Reusable building blocks".
4. Apple's own Liquid Glass and SwiftUI docs bundled inside Xcode. Find them with `find /Applications/Xcode*.app -type d -name AdditionalDocumentation 2>/dev/null` and read anything about Liquid Glass, SwiftUI animations and macOS windows. These beat your memory if they disagree.

## Use these tools
- **Skills and plugins:**
  - Use the **superpowers** plugin's workflow: brainstorm, then write a plan, execute it in small verified steps, use TDD for pure logic, debug systematically, and verify before claiming done.
  - Use the **liquid-glass** skill for every piece of UI, and the **hig-\*** skills (foundations, platforms, patterns, components) for layout, typography, motion and settings design.
  - If any of these aren't installed, tell me which ones are missing and carry on.
- **Xcode MCP server (`xcode`):** use it for builds, diagnostics and tests when connected; otherwise use `xcodebuild`.
- **Screenshots:** take them with `screencapture -x`. After every UI change, build, install to `~/Applications/DynamicNotch.app`, launch, screenshot the island (compact, hovered/expanded, and on a non-notch display if one is connected), then **look at the image** and critique it against Apple's Dynamic Island and the macOS 26/27 system UI. Iterate until it's genuinely good, not just functional.
- **Reference repos:** read them on GitHub, respecting the licence rules in CLAUDE.md. Use DynamicNotchKit (MIT) and boring.notch (GPL-3.0, which we're allowed to adapt with attribution) for window and geometry code. Never copy from SuperIsland or closed apps.

## Step 0: Plan (you're in plan mode)
Before writing any code, produce a plan for M1 and wait for my approval. The plan must include:
- **The file tree you'll create.** Follow the architecture in CLAUDE.md.
- **The XcodeGen `project.yml` design.** Cover the targets (app plus a unit-test target), deployment target macOS 26.0, Swift 6 language mode, Hardened Runtime, no sandbox, `LSUIElement`, and the Info.plist usage strings you'll need later. Find my Apple Development signing team with `security find-identity -v -p codesigning` and propose it as `DEVELOPMENT_TEAM`.
- **Key type signatures:**
  - `IslandModule`
  - `Activity`
  - `ActivityCoordinator`
  - `NotchGeometry`
  - `IslandPanel`
  - `IslandController`
  - `RefreshScheduler`
  - `PermissionCenter`
  - `SettingsStore`
  - Design tokens
- **How you'll solve the hardest M1 problems:**
  - Click-through around the island while still detecting hover (#7)
  - Fullscreen detection (#5)
  - Multi-display handling
  - A single continuous morph between compact and expanded
- **The order of implementation steps,** each small enough to build and verify on its own.
- **Any questions for me.** Ask instead of assuming.

## Then: build M1
Once I approve, implement M1 in this order. Build, test, install, launch and screenshot after each step, then commit:

1. **Scaffolding.**
   - `git init`, `.gitignore` (Xcode, `build/`, DerivedData, `.DS_Store`)
   - `LICENSE` (full GPL-3.0 text from https://www.gnu.org/licenses/gpl-3.0.txt)
   - `THIRD_PARTY_NOTICES.md`
   - `README.md` with build steps
   - `project.yml`
   - `xcodegen generate`
   - An empty menu-bar agent app that builds, signs and launches
2. **NotchGeometry + IslandPanel.** A black compact island that sits exactly on the hardware notch (or a pill below the menu bar on non-notch screens), with unit tests for the geometry maths. Handle screen changes, sleep and wake, and display connect and disconnect.
3. **Compact ↔ expanded morph** (#1) on hover and click, as one continuous shape with spring tokens.
   - The expanded view for M1: a header (time and date), a placeholder content area that later modules fill, and a row of glass buttons (Settings, Pause).
   - Respect Reduce Motion and Reduce Transparency.
4. **Click-through** (#7) and **auto-hide in fullscreen** (#5). Verify by clicking menu items beside the notch and by fullscreening Safari and another app.
5. **ActivityCoordinator + IslandModule + ModuleRegistry.**
   - Start test-first: the priority, transient-expiry and leading/trailing slot rules are pure logic.
   - Add a DEBUG-only "Hello" demo activity, triggered from the status menu, that proves the whole pipeline.
6. **SettingsStore + Settings window.**
   - The window is a native macOS 26 settings window with a sidebar: General, Appearance, Modules, Permissions, About.
   - **#70:** per-module toggles.
   - **#72:** a size, hover-delay and animation-style live preview.
   - **#73:** themes per display type ("Notch black", "Liquid Glass", "Tinted glass").
   - **#6:** a "Hide from screenshots" toggle.
7. **#77.**
   - The status item menu: Settings…, Pause island, About, Quit.
   - Launch at login via `SMAppService`.
   - `PermissionCenter`, which shows live TCC status with deep links to System Settings.
   - A short, beautiful **first-run onboarding**: welcome → choose modules → permissions → done.
8. **Polish pass.**
   - Review every screen against the HIG and Liquid Glass skills: spacing on a 4/8 pt grid, continuous corners, SF Symbols with symbol effects, typography, and dark/light/increased-contrast appearances.
   - Then run the performance check from CLAUDE.md (idle CPU < 0.5%, memory < 120 MB) and fix anything over budget.

## Definition of done for M1
- The app builds with zero warnings in Swift 6 mode, all tests pass, and it runs from `~/Applications`.
- Screenshots show a pixel-aligned island on the notch, a smooth expanded state, and a correct pill on non-notch screens (simulate one if needed by forcing the non-notch geometry path through a debug setting).
- Menus beside the notch stay clickable. The island hides in fullscreen. Every setting works and persists across relaunches.
- Idle CPU and memory are within budget. Measure them and report the numbers.
- `docs/ROADMAP.md` M1 rows are marked ✅. ADRs exist for non-obvious decisions. Commits are clean.
- Finish with a short report:
  - What you built
  - The screenshots
  - Measured CPU and memory
  - Any compromises or open questions
  - What you suggest for M2

If something in the spec turns out to be impossible or wrong on macOS 27.2, stop and tell me rather than working around it silently.
