We're continuing Notched, **M3a Part B**. Part A was written in a Linux cloud container with no Xcode: the six modules' logic, `ModuleHost`, the banner system, docs and 195 tests were written and tested there with a Swift 6.2 toolchain, but **nothing has ever been compiled with Xcode or run on a Mac**. Treat all of Part A as unreviewed code. This session builds it for real, fixes it, finishes the UI, and verifies on this Mac.

## Step 0: Get the code (do this first, before reading anything else)
1. Check `git status`. If there are uncommitted changes, stop and show me.
2. `git fetch origin`, then check out `claude/notched-m3a-status-modules-5rqpq8` (it branches from `main` after the M2 merge). Confirm with `git log --oneline -20` that it has 17 new commits. If local `main` is behind `origin/main`, tell me before doing anything.
3. Create a working branch from it, `m3a-status`, so my local work stays separate. Don't push without asking.
4. Run `xcodegen generate`.

## Read first
1. `CLAUDE.md` (binding; includes Token economy: send builds and tests to the `build-runner` subagent, searches to `Explore`).
2. `docs/superpowers/plans/2026-10-28-m3a-status.md`: **start with the handoff section at the end.** It lists exactly which files to check first and which assumptions are unverified. Then read the spec beside it.
3. The two new ADRs (music stays primary; banner pipeline), ADR-0006 and ADR-0007.
4. `docs/prompts/M3a-status-alerts.md`: the original brief this work was written against, for the definition of done.

## Tools
- **superpowers:** systematic-debugging for every compile or test failure, verification-before-completion at the end. TDD for anything you add.
- **liquid-glass + hig-\*** for the UI work. The iPhone Dynamic Island banners are the reference.
- **Xcode MCP** (fallback `xcodebuild`), `screencapture`; look at every screenshot and critique it.

## Task list for this session
### B1. Make it build
- Build the app and test targets. Fix compile errors one at a time (expect Swift 6 strict-concurrency errors, AppKit/IOKit API differences and missing imports: the code was never compiled against the macOS SDK). Don't weaken concurrency checking to silence errors; fix them properly.
- Run the full test suite. The Linux run passed 195 tests, so any failure here is a platform difference worth understanding, not just patching. Report each one.
- Commit: `fix: build M3a against the macOS SDK`.

### B2. Check the unverified assumptions (write findings to an ADR)
Answer each by experiment on this Mac (macOS 27.2) and record the result:
1. Does the **Caps Lock** global `NSEvent` monitor work with no Accessibility permission? If not, make the module explain this in Settings (it already defaults to off).
2. Does the **Bluetooth device list** (keyboards, mice, trackpads, controllers) work with **no permission prompt**? If a prompt appears, decide with me before shipping it.
3. Do the **SF Symbol names** the code uses exist (magicmouse, the trackpad symbol, and anything else)? Write a small test that instantiates every symbol name used in the modules, so a typo fails a test.
4. Does the **charger timing** (1 s settle, "Plugged In" when a charge limit holds) behave correctly on this Mac? Plug and unplug, and tell me if I need to do something physical.
5. Does `ModuleHost` crash protection behave: simulate a module that crashes at start twice, then three quick crashes, and confirm safe mode and "Resume Modules" in the menu bar. Safe mode must not trigger while a debugger is attached.

### B3. Make each module real
For each module (battery, Bluetooth, network, Caps Lock, keep-awake, timers/stopwatch), in this order: **build, install, run, screenshot, critique, fix, commit.**
- Drive each one for real wherever possible (a timer, keep-awake, Wi-Fi off/on, the charger). Use the DEBUG Scenario Lab only for what can't be triggered (full battery, low battery).
- For anything that needs me (AirPods connect, unplugging a charger, deny/allow of a permission), stop and give me a short numbered list of exactly what to do, then continue when I reply.
- Check that the UI actually follows the brief: banner look and timing, the three-activity layout (music primary, timer and keep-awake as bubbles), timer alert expansion with sound even when alert expansion is off, the `notched://timer?minutes=10&label=Tea` URL, and timers surviving sleep/wake and app relaunch.
- Reduce Motion, Reduce Transparency and the non-notch pill must all work. Take a screenshot of each module on the pill too.

### B4. Verify
- Screenshots in `docs/screenshots/m3a/` as listed in `docs/prompts/M3a-status-alerts.md`.
- Robustness: sleep/wake with timers and keep-awake running, quit and relaunch with a running timer, Wi-Fi off/on repeatedly (no banner spam), enable and disable every module repeatedly with **no leaked IOPM assertions, listeners or timers** (check with `pmset -g assertions` and by counting listeners in a test).
- Performance with all M3a modules on, using `scripts/cpu.sh`: idle < 0.5%, Now Playing compact < 1.5%, a timer running compact < 1%, memory < 150 MB. If a timer or ring costs more than budget, fix it before moving on (use the Core Animation approach from ADR-0010, not a SwiftUI per-frame timeline).
- Update `docs/ROADMAP.md`: mark each row ✅ (or 🟨 with the reason) with measured numbers.
- Run the superpowers verification-before-completion check, and request a fresh review of the whole branch (a clean subagent that hasn't seen the work); fix every critical and important finding.

## Rules
- If the plan or spec turns out wrong on a real Mac, stop and tell me rather than quietly doing something different.
- Don't merge or push. At the end I'll decide.
- Finish with a short report: build/test results, the answers to B2 (1–5), screenshots, performance numbers, what works and doesn't on macOS 27.2, decisions made, anything I need to try myself, and suggestions for M3b.
