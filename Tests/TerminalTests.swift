// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI
import Testing
@testable import Notched

/// The Terminal's shell launch, lifecycle and cleanup (#64).
@Suite("Terminal logic")
struct TerminalLogicTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Shell

    @Test("$SHELL is used when it's an absolute, executable path; anything else falls back to zsh")
    func resolvingShell() {
        let present: (String) -> Bool = { $0 == "/opt/homebrew/bin/fish" }
        #expect(ShellLauncher.resolveShell(environmentShell: "/opt/homebrew/bin/fish", isExecutable: present) == "/opt/homebrew/bin/fish")
        #expect(ShellLauncher.resolveShell(environmentShell: "/usr/local/bin/gone", isExecutable: present) == "/bin/zsh")
        #expect(ShellLauncher.resolveShell(environmentShell: "fish", isExecutable: { _ in true }) == "/bin/zsh")
        #expect(ShellLauncher.resolveShell(environmentShell: "/bin/zsh\n/bin/evil", isExecutable: { _ in true }) == "/bin/zsh")
        #expect(ShellLauncher.resolveShell(environmentShell: nil, isExecutable: { _ in true }) == "/bin/zsh")
        #expect(ShellLauncher.resolveShell(environmentShell: "", isExecutable: { _ in true }) == "/bin/zsh")
    }

    @Test("The shell starts as a login shell through sh, with the folder and shell passed as arguments, never spliced into the script")
    func launchPlan() {
        let home = #"/Users/o'brien "quoted"; rm -rf $HOME"#
        let launch = ShellLauncher.launch(shell: "/bin/zsh", home: home)
        #expect(launch.executable == "/bin/sh")
        #expect(launch.args.count == 4 && launch.args[0] == "-c")
        #expect(launch.args[2] == "/bin/zsh" && launch.args[3] == home)
        #expect(launch.args[1].contains("exec \"$0\" -l"))
        #expect(!launch.args[1].contains("brien") && !launch.args[1].contains("/bin/zsh"))
    }

    @Test("The launch plan really runs the shell inside the home folder, run with a real sh")
    func launchPlanRuns() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Term Test \(UUID().uuidString)")
        let home = root.appendingPathComponent("home dir")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A script stands in for the login shell, so the test doesn't depend on this Mac's startup files.
        let fakeShell = root.appendingPathComponent("fake shell")
        try "#!/bin/sh\npwd -P\n".write(to: fakeShell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeShell.path)

        let launch = ShellLauncher.launch(shell: fakeShell.path, home: home.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.args
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        #expect(output == home.resolvingSymlinksInPath().path)
        #expect(process.terminationStatus == 0)
    }

    // MARK: Lifecycle

    @Test("The first time the tab shows, a shell starts; showing it again while it runs does nothing")
    func firstShow() {
        var sut = TerminalLifecycleReducer()
        #expect(sut.reduce(.tabShown, now: t0) == [.start(generation: 1)])
        #expect(sut.state.phase == .running)
        #expect(sut.reduce(.tabShown, now: t0 + 5).isEmpty)
    }

    @Test("A shell that exits normally gives a fresh one the next time the tab shows")
    func restartsAfterNormalExit() {
        var sut = TerminalLifecycleReducer()
        _ = sut.reduce(.tabShown, now: t0)
        _ = sut.reduce(.processExited(code: 0, generation: 1), now: t0 + 60)
        #expect(sut.state.phase == .ended(code: 0, reason: .shellExited))
        #expect(sut.reduce(.tabShown, now: t0 + 90) == [.start(generation: 2)])
    }

    @Test("A shell that dies at once, twice, stops being restarted by showing the tab; New Session does it and resets")
    func crashLoop() {
        var sut = TerminalLifecycleReducer()
        _ = sut.reduce(.tabShown, now: t0)
        _ = sut.reduce(.processExited(code: 1, generation: 1), now: t0 + 0.2)
        #expect(!sut.isGivenUp)
        #expect(sut.reduce(.tabShown, now: t0 + 1) == [.start(generation: 2)])
        _ = sut.reduce(.processExited(code: 1, generation: 2), now: t0 + 1.3)
        #expect(sut.isGivenUp)
        #expect(sut.reduce(.tabShown, now: t0 + 2).isEmpty)
        #expect(sut.reduce(.newSession, now: t0 + 3) == [.start(generation: 3)])
        #expect(!sut.isGivenUp)
    }

    @Test("A shell that ran a while before exiting resets the count")
    func slowExitResets() {
        var sut = TerminalLifecycleReducer()
        _ = sut.reduce(.tabShown, now: t0)
        _ = sut.reduce(.processExited(code: 1, generation: 1), now: t0 + 0.2)
        _ = sut.reduce(.tabShown, now: t0 + 1)
        _ = sut.reduce(.processExited(code: 0, generation: 2), now: t0 + 600)
        #expect(sut.state.quickExits == 0)
    }

    @Test("An exit report from an old shell can't end the new one")
    func staleGeneration() {
        var sut = TerminalLifecycleReducer()
        _ = sut.reduce(.tabShown, now: t0)
        _ = sut.reduce(.newSession, now: t0 + 5)                           // generation 2
        #expect(sut.reduce(.processExited(code: nil, generation: 1), now: t0 + 6).isEmpty)
        #expect(sut.state.phase == .running)
    }

    @Test("Ending the session terminates once, and the shell's own exit report afterwards is ignored")
    func endSession() {
        var sut = TerminalLifecycleReducer()
        _ = sut.reduce(.tabShown, now: t0)
        #expect(sut.reduce(.endSession, now: t0 + 5) == [.terminate])
        #expect(sut.state.phase == .ended(code: nil, reason: .userEnded))
        #expect(sut.reduce(.processExited(code: 1, generation: 1), now: t0 + 5.1).isEmpty)
        #expect(sut.state.phase == .ended(code: nil, reason: .userEnded))
        #expect(sut.reduce(.endSession, now: t0 + 6).isEmpty)
        #expect(sut.reduce(.tabShown, now: t0 + 7) == [.start(generation: 2)])
    }

    @Test("New Session while one runs ends it and starts another")
    func newSessionReplaces() {
        var sut = TerminalLifecycleReducer()
        _ = sut.reduce(.tabShown, now: t0)
        #expect(sut.reduce(.newSession, now: t0 + 5) == [.terminate, .start(generation: 2)])
    }

    @Test("Stopping terminates a running shell and forgets everything, and does nothing for one that is not running")
    func stop() {
        var sut = TerminalLifecycleReducer()
        #expect(sut.reduce(.stop, now: t0).isEmpty)
        _ = sut.reduce(.tabShown, now: t0)
        #expect(sut.reduce(.stop, now: t0 + 1) == [.terminate])
        #expect(sut.state.phase == .notStarted)
        // A late exit report after stopping starts nothing.
        #expect(sut.reduce(.processExited(code: nil, generation: 1), now: t0 + 2).isEmpty)
        #expect(sut.reduce(.tabShown, now: t0 + 3) == [.start(generation: 2)])
    }

    @Test("Random events: a start is always for the newest generation, terminate only follows a running shell")
    func fuzz() {
        var generator = SystemRandomNumberGenerator()
        var sut = TerminalLifecycleReducer()
        var now = t0
        for _ in 0..<1000 {
            now += TimeInterval.random(in: 0...3, using: &generator)
            let before = sut.state
            let event: TerminalLifecycleReducer.Event = switch Int.random(in: 0..<6, using: &generator) {
            case 0: .tabShown
            case 1: .processExited(code: Int32.random(in: 0...2, using: &generator), generation: Int.random(in: 0...max(1, before.generation), using: &generator))
            case 2: .newSession
            case 3: .endSession
            case 4: .stop
            default: .tabShown
            }
            let effects = sut.reduce(event, now: now)
            for effect in effects {
                switch effect {
                case .start(let generation): #expect(generation == sut.state.generation && sut.state.phase == .running)
                case .terminate: #expect(before.phase == .running)
                }
            }
            #expect(effects.filter { if case .start = $0 { true } else { false } }.count <= 1)
            #expect(sut.state.generation >= before.generation)
        }
    }

    // MARK: Cleanup

    @Test("The killer ends a real process and leaves none running")
    func killerEndsProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 30"]
        try process.run()
        let pid = process.processIdentifier
        #expect(TerminalProcessKiller.isAlive(pid))
        TerminalProcessKiller.terminate(pid: pid)
        process.waitUntilExit()
        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
    }

    @Test("It escalates to SIGKILL when the process ignores the hang-up")
    func killerEscalates() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Ignores HUP and TERM, and keeps a foreground job so sh doesn't exec it away.
        process.arguments = ["-c", "trap '' HUP TERM; sleep 5; sleep 5"]
        try process.run()
        Thread.sleep(forTimeInterval: 0.15)
        TerminalProcessKiller.terminate(pid: process.processIdentifier, grace: 0.2)
        process.waitUntilExit()
        #expect(!process.isRunning)
    }

    @Test("It never signals pid 0, 1 or a negative pid")
    func killerRefusesBadPIDs() {
        TerminalProcessKiller.terminate(pid: 0)
        TerminalProcessKiller.terminate(pid: 1)
        TerminalProcessKiller.terminate(pid: -5)
        #expect(TerminalProcessKiller.isAlive(getpid()))
    }
}

/// How the island treats the keyboard for a tab that types keys itself (ADR-0026).
@Suite("IslandKeyboardPolicy")
struct IslandKeyboardPolicyTests {
    @Test("Esc goes to the shell, ⌘Esc collapses, and other tabs keep Esc as collapse")
    func escape() {
        #expect(IslandKeyboardPolicy.escape(capturesKeyboard: true, command: false) == .passToContent)
        #expect(IslandKeyboardPolicy.escape(capturesKeyboard: true, command: true) == .collapse)
        #expect(IslandKeyboardPolicy.escape(capturesKeyboard: false, command: false) == .collapse)
        #expect(IslandKeyboardPolicy.escape(capturesKeyboard: false, command: true) == .collapse)
    }

    @Test("The island stays open on pointer exit only for a capturing tab with focus or a pin")
    func holdsOpen() {
        #expect(IslandKeyboardPolicy.holdsOpen(capturesKeyboard: true, pinned: false, hasKeyFocus: true))
        #expect(IslandKeyboardPolicy.holdsOpen(capturesKeyboard: true, pinned: true, hasKeyFocus: false))
        #expect(!IslandKeyboardPolicy.holdsOpen(capturesKeyboard: true, pinned: false, hasKeyFocus: false))
        #expect(!IslandKeyboardPolicy.holdsOpen(capturesKeyboard: false, pinned: true, hasKeyFocus: true))
    }

    @Test("Losing focus to another app closes the island unless it is pinned or the pointer is on it")
    func losingFocus() {
        #expect(IslandKeyboardPolicy.collapsesAfterLosingFocus(capturesKeyboard: true, pinned: false, pointerInside: false))
        #expect(!IslandKeyboardPolicy.collapsesAfterLosingFocus(capturesKeyboard: true, pinned: true, pointerInside: false))
        #expect(!IslandKeyboardPolicy.collapsesAfterLosingFocus(capturesKeyboard: true, pinned: false, pointerInside: true))
        #expect(!IslandKeyboardPolicy.collapsesAfterLosingFocus(capturesKeyboard: false, pinned: false, pointerInside: false))
    }

    @Test("⌘C, ⌘V and ⌘A are forwarded only for a capturing tab and only with ⌘ alone")
    func editCommands() {
        func command(_ key: String, command: Bool = true, control: Bool = false, shift: Bool = false, option: Bool = false, captures: Bool = true) -> IslandKeyboardPolicy.EditCommand? {
            IslandKeyboardPolicy.editCommand(characters: key, command: command, control: control, shift: shift, option: option, capturesKeyboard: captures)
        }
        #expect(command("c") == .copy && command("V") == .paste && command("a") == .selectAll)
        #expect(command("c", captures: false) == nil)
        #expect(command("c", command: false) == nil)
        #expect(command("c", control: true) == nil && command("c", shift: true) == nil && command("c", option: true) == nil)
        #expect(command("x") == nil)
        #expect(IslandKeyboardPolicy.editCommand(characters: nil, command: true, control: false, shift: false, option: false, capturesKeyboard: true) == nil)
    }

    @Test("A capturing tab keeps the plain arrow keys; tab shortcuts still work")
    func arrowsBelongToTheContent() {
        func key(_ code: UInt16, _ characters: String? = nil, command: Bool = false, control: Bool = false, captures: Bool) -> ExpandedKeyCommand? {
            ExpandedTabs.command(keyCode: code, characters: characters, command: command, control: control, shift: false, option: false, capturesKeyboard: captures)
        }
        #expect(key(123, captures: false) == .pageBack && key(124, captures: false) == .pageForward)
        #expect(key(123, captures: true) == nil && key(124, captures: true) == nil)
        #expect(key(18, "1", command: true, captures: true) == .selectTab(0))
        #expect(key(48, control: true, captures: true) == .nextTab)
    }
}

/// The taller island the Terminal asks for.
@Suite("Taller tabs")
@MainActor
struct TallTabTests {
    private func make() -> (IslandViewModel, ActivityCoordinator) {
        let activities = ActivityCoordinator()
        let model = IslandViewModel(geometry: NotchGeometry.resolve(NotchGeometryTests.air15), accessibility: AccessibilityOptions(), activities: activities)
        return (model, activities)
    }

    private func tab(_ id: String, tall: CGFloat? = nil) -> IslandTab {
        IslandTab(id: id, moduleID: "m", title: id, symbol: "star", capturesKeyboard: tall != nil, maxContentHeight: tall) { Text(id) }
    }

    @Test("Without a tall tab the island keeps its usual limit")
    func usual() {
        let (model, activities) = make()
        activities.setTabs([tab("a")], from: "m")
        #expect(model.maxExpandedHeight == model.headerHeight + IslandMetrics.expandedMaxContentHeight)
    }

    @Test("A tall tab raises the panel's size, but only that tab may use the extra height")
    func tall() {
        let (model, activities) = make()
        activities.setTabs([tab("a"), tab("t", tall: 310)], from: "m")
        #expect(model.maxExpandedHeight == model.headerHeight + 310)
        #expect(model.maxExpandedHeight(for: model.tabs.first { $0.id == "a" }) == model.headerHeight + IslandMetrics.expandedMaxContentHeight)

        model.reportExpandedHeight(300, for: "tab.a")
        model.reportExpandedHeight(300, for: "tab.t")
        _ = model.selectTab("a")
        let normal = model.expandedHeight
        _ = model.selectTab("t")
        #expect(model.expandedHeight > normal)
        #expect(model.expandedHeight <= model.headerHeight + 310)
    }

    @Test("Removing the tall tab brings the panel back to its usual size")
    func removed() {
        let (model, activities) = make()
        activities.setTabs([tab("t", tall: 310)], from: "m")
        activities.endAll(from: "m")
        #expect(model.maxExpandedHeight == model.headerHeight + IslandMetrics.expandedMaxContentHeight)
    }

    @Test("The Terminal module's tab captures the keyboard, asks for room and follows the pin")
    func terminalTab() {
        let coordinator = ActivityCoordinator()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "TerminalTabTests.\(UUID().uuidString)")!)
        let context = ModuleContext(activities: ActivitySink(moduleID: TerminalModule.descriptor.id, coordinator: coordinator),
                                    scheduler: RefreshScheduler(), settings: settings, services: ModuleServices(), previousSessionCrashed: false)
        let module = TerminalModule(context: context)
        module.start()
        let tab = coordinator.moduleTabs.first
        #expect(tab?.id == "terminal" && tab?.capturesKeyboard == true)
        #expect((tab?.maxContentHeight ?? 0) > IslandMetrics.expandedMaxContentHeight)
        #expect(tab?.keepsIslandOpen?() == false)
        module.model.isPinned = true
        #expect(tab?.keepsIslandOpen?() == true)
        // Nothing runs until the tab is shown.
        #expect(module.model.session == nil && module.shellPID == 0)
        module.stop()
        #expect(coordinator.moduleTabs.isEmpty)
        #expect(!module.model.isPinned)
    }
}
