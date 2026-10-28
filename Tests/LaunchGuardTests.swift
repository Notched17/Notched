// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("LaunchGuard")
struct LaunchGuardTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

    /// A session that crashed while `module` was starting (or, with nil, later on).
    private func crashed(startingModule module: ModuleID? = nil, stable: Bool = false, base: LaunchRecord = LaunchRecord()) -> LaunchRecord {
        var record = base
        record.sessionOpen = true
        record.sessionStable = stable
        record.startingModule = module
        return record
    }

    @Test("A clean quit is not a crash")
    func cleanExitIsNotACrash() {
        var sut = LaunchGuard(record: LaunchRecord())
        sut.launch(at: t0, debuggerAttached: false)
        sut.willStart("a")
        sut.didStart("a")
        sut.cleanExit()
        var next = LaunchGuard(record: sut.record)
        next.launch(at: t0 + 60, debuggerAttached: false)
        #expect(!next.previousSessionCrashed)
        #expect(next.record.strikes.isEmpty)
        #expect(!next.isSafeMode)
    }

    @Test("A crash while a module starts gives that module a strike")
    func crashDuringStartStrikes() {
        var sut = LaunchGuard(record: crashed(startingModule: "a"))
        sut.launch(at: t0, debuggerAttached: false)
        #expect(sut.previousSessionCrashed)
        #expect(sut.record.strikes == ["a": 1])
        #expect(sut.record.suspended.isEmpty)
        #expect(sut.record.startingModule == nil)
        #expect(sut.record.sessionOpen)
    }

    @Test("Two strikes suspend the module")
    func twoStrikesSuspend() {
        var base = LaunchRecord()
        base.strikes = ["a": 1]
        var sut = LaunchGuard(record: crashed(startingModule: "a", base: base))
        sut.launch(at: t0, debuggerAttached: false)
        #expect(sut.record.suspended == ["a"])
    }

    @Test("A crash after start-up blames no module")
    func crashLaterBlamesNoModule() {
        var sut = LaunchGuard(record: crashed(stable: true))
        sut.launch(at: t0, debuggerAttached: false)
        #expect(sut.previousSessionCrashed)
        #expect(sut.record.strikes.isEmpty)
        #expect(sut.record.quickCrashes.isEmpty)
    }

    @Test("A stable session clears the strikes of the modules that ran")
    func stableSessionClearsStrikes() {
        var base = LaunchRecord()
        base.strikes = ["a": 1, "b": 1]
        var sut = LaunchGuard(record: base)
        sut.launch(at: t0, debuggerAttached: false)
        sut.markStable(running: ["a"])
        #expect(sut.record.strikes == ["b": 1])
        #expect(sut.record.sessionStable)
    }

    @Test("Three quick crashes in ten minutes enter safe mode")
    func threeQuickCrashesEnterSafeMode() {
        var base = LaunchRecord()
        base.quickCrashes = [t0 - 120, t0 - 60]
        var sut = LaunchGuard(record: crashed(base: base))
        sut.launch(at: t0, debuggerAttached: false)
        #expect(sut.record.quickCrashes.count == 3)
        #expect(sut.isSafeMode)
    }

    @Test("Quick crashes older than ten minutes are forgotten")
    func quickCrashesExpireAfterTenMinutes() {
        var base = LaunchRecord()
        base.quickCrashes = [t0 - 900, t0 - 700]
        var sut = LaunchGuard(record: crashed(base: base))
        sut.launch(at: t0, debuggerAttached: false)
        #expect(sut.record.quickCrashes == [t0])
        #expect(!sut.isSafeMode)
    }

    @Test("Never safe mode under a debugger: Xcode's Stop button kills the app")
    func debuggerNeverEntersSafeMode() {
        var base = LaunchRecord()
        base.quickCrashes = [t0 - 120, t0 - 60]
        var sut = LaunchGuard(record: crashed(base: base))
        sut.launch(at: t0, debuggerAttached: true)
        #expect(!sut.isSafeMode)
    }

    @Test("Resuming a module clears its suspension and strikes")
    func resumeClearsSuspension() {
        var base = LaunchRecord()
        base.strikes = ["a": 2]
        base.suspended = ["a"]
        var sut = LaunchGuard(record: base)
        sut.resume("a")
        #expect(sut.record.suspended.isEmpty)
        #expect(sut.record.strikes.isEmpty)
    }

    @Test("Leaving safe mode, or a stable session, ends the crash streak")
    func stableSessionEndsSafeModeStreak() {
        var base = LaunchRecord()
        base.quickCrashes = [t0 - 120, t0 - 60]
        var sut = LaunchGuard(record: crashed(base: base))
        sut.launch(at: t0, debuggerAttached: false)
        #expect(sut.isSafeMode)
        sut.leaveSafeMode()
        #expect(!sut.isSafeMode)
        #expect(sut.record.quickCrashes.isEmpty)

        var stable = LaunchGuard(record: crashed(base: base))
        stable.launch(at: t0, debuggerAttached: false)
        stable.markStable(running: [])
        #expect(stable.record.quickCrashes.isEmpty)
    }

    @Test("The record survives a JSON round trip")
    func codable() throws {
        var record = LaunchRecord()
        record.sessionOpen = true
        record.startingModule = "media"
        record.strikes = ["media": 1]
        record.quickCrashes = [t0]
        record.suspended = ["battery"]
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(LaunchRecord.self, from: data) == record)
    }
}
