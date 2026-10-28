// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the last launches left behind, persisted so a crash can be noticed
/// at the next launch (UserDefaults hands each write to cfprefsd at once, so
/// it survives the app crashing).
struct LaunchRecord: Codable, Equatable, Sendable {
    /// Set at launch and cleared on a clean quit: still set at the next
    /// launch means the app crashed or was killed.
    var sessionOpen = false
    /// The session has run for `LaunchGuard.stableAfter`.
    var sessionStable = false
    /// The session runs under a debugger: Xcode's Stop button kills it, so
    /// its unclean end isn't a crash.
    var sessionDebugged = false
    /// Set just before a module's `start()` and cleared right after.
    var startingModule: ModuleID?
    /// Crashes while each module was starting.
    var strikes: [ModuleID: Int] = [:]
    /// When recent sessions crashed before becoming stable.
    var quickCrashes: [Date] = []
    /// Modules turned off for crashing at start, until the user turns them back on.
    var suspended: Set<ModuleID> = []
}

extension LaunchRecord {
    /// Reads records saved by older versions too: a missing key keeps its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionOpen = try container.decodeIfPresent(Bool.self, forKey: .sessionOpen) ?? false
        sessionStable = try container.decodeIfPresent(Bool.self, forKey: .sessionStable) ?? false
        sessionDebugged = try container.decodeIfPresent(Bool.self, forKey: .sessionDebugged) ?? false
        startingModule = try container.decodeIfPresent(ModuleID.self, forKey: .startingModule)
        strikes = try container.decodeIfPresent([ModuleID: Int].self, forKey: .strikes) ?? [:]
        quickCrashes = try container.decodeIfPresent([Date].self, forKey: .quickCrashes) ?? []
        suspended = try container.decodeIfPresent(Set<ModuleID>.self, forKey: .suspended) ?? []
    }
}

/// Crash-loop protection for modules (ModuleHost). Pure: the host feeds it
/// lifecycle moments and persists `record` after each one.
///
/// - A crash while a module was starting is that module's strike; two
///   strikes suspend it.
/// - Three sessions that crash within 30 s of launch, inside ten minutes,
///   start the next launch in safe mode: no modules at all. Never under a
///   debugger, since Xcode's Stop button kills the app; and a session that
///   ran under one isn't counted as a crash at all.
/// - A session that stays up 30 s clears the strikes of the modules it ran,
///   and the quick-crash streak.
struct LaunchGuard: Sendable {
    static let strikesToSuspend = 2
    static let stableAfter: TimeInterval = 30
    static let quickCrashesForSafeMode = 3
    static let quickCrashMemory: TimeInterval = 10 * 60

    private(set) var record: LaunchRecord
    /// The previous session didn't quit cleanly. Features that must not come
    /// back after a crash (keep-awake, later the lock screen) check this.
    private(set) var previousSessionCrashed = false
    private(set) var isSafeMode = false

    init(record: LaunchRecord) {
        self.record = record
    }

    /// Judges the previous session, then opens a new one.
    mutating func launch(at now: Date, debuggerAttached: Bool) {
        previousSessionCrashed = record.sessionOpen && !record.sessionDebugged
        if previousSessionCrashed {
            if let module = record.startingModule {
                let strikes = record.strikes[module, default: 0] + 1
                record.strikes[module] = strikes
                if strikes >= Self.strikesToSuspend { record.suspended.insert(module) }
            }
            if !record.sessionStable { record.quickCrashes.append(now) }
        }
        record.quickCrashes.removeAll { now.timeIntervalSince($0) > Self.quickCrashMemory }
        isSafeMode = !debuggerAttached && record.quickCrashes.count >= Self.quickCrashesForSafeMode
        record.sessionOpen = true
        record.sessionStable = false
        record.sessionDebugged = debuggerAttached
        record.startingModule = nil
    }

    mutating func willStart(_ module: ModuleID) {
        record.startingModule = module
    }

    mutating func didStart(_ module: ModuleID) {
        if record.startingModule == module { record.startingModule = nil }
    }

    mutating func markStable(running: Set<ModuleID>) {
        record.sessionStable = true
        record.quickCrashes = []
        for module in running { record.strikes[module] = nil }
    }

    mutating func cleanExit() {
        record.sessionOpen = false
        record.startingModule = nil
    }

    mutating func resume(_ module: ModuleID) {
        record.suspended.remove(module)
        record.strikes[module] = nil
    }

    mutating func leaveSafeMode() {
        isSafeMode = false
        record.quickCrashes = []
    }
}
