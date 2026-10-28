// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How long keep-awake lasts (#38).
enum KeepAwakePreset: Equatable, Sendable, CaseIterable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case indefinitely

    /// Seconds; nil for indefinitely.
    var duration: TimeInterval? {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .indefinitely: nil
        }
    }
}

/// Keep-awake (#38): keeps the display awake with one power assertion.
/// Pure; the shell carries out `.acquire`/`.release` with
/// `IOPMAssertionCreateWithName(PreventUserIdleDisplaySleep)`.
///
/// - At most one assertion is ever held: a preset change while on only
///   reschedules. Stop, the end time, a wake past it, a failed acquire and
///   quitting all release it (pinned by a fuzz test).
/// - Never restored after relaunch: quitting turns it off, and a crash
///   releases the assertion in the kernel.
struct KeepAwakeReducer: Sendable {
    enum Mode: Equatable, Sendable {
        case off
        /// Until this date; nil for indefinitely.
        case on(until: Date?)
    }

    enum Event: Equatable, Sendable {
        case start(KeepAwakePreset)
        case stop
        /// The end-time wake the reducer scheduled.
        case deadline
        /// The Mac woke from sleep.
        case wake
        /// macOS refused the assertion.
        case acquireFailed
        case quit
    }

    enum Effect: Equatable, Sendable {
        case acquire
        case release
        /// Post (or update) the activity, counting down to `until`.
        case post(until: Date?)
        case end
        case schedule(Date?)
    }

    private(set) var mode: Mode = .off
    private(set) var assertionHeld = false

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .start(let preset):
            let until = preset.duration.map { now.addingTimeInterval($0) }
            var effects: [Effect] = []
            if !assertionHeld {
                assertionHeld = true
                effects.append(.acquire)
            }
            mode = .on(until: until)
            return effects + [.post(until: until), .schedule(until)]
        case .stop, .quit:
            return turnOff()
        case .deadline, .wake:
            guard case .on(let until?) = mode else { return [] }
            return until <= now ? turnOff() : [.schedule(until)]
        case .acquireFailed:
            guard assertionHeld else { return [] }
            assertionHeld = false
            mode = .off
            return [.end, .schedule(nil)]
        }
    }

    private mutating func turnOff() -> [Effect] {
        guard mode != .off || assertionHeld else { return [] }
        var effects: [Effect] = []
        if assertionHeld {
            assertionHeld = false
            effects.append(.release)
        }
        mode = .off
        return effects + [.end, .schedule(nil)]
    }
}
