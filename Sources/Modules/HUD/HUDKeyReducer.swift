// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Why the HUD stopped intercepting keys.
enum HUDStopReason: String, Codable, Sendable {
    case timeouts, slowCallbacks, permissionRevoked, uncleanExits
}

/// What the HUD does with each volume or brightness key press (the safety
/// design §3). Pure: the engine feeds it events and the time, and carries out
/// the effects.
///
/// A key goes to macOS unless the HUD is armed, trusted and visible, the
/// modifiers are ones it owns, and the change then takes effect. Each press
/// is paired with its key-up: macOS gets the key-up of any press it saw a down
/// of. An output that accepts a change but never reports it (a Bluetooth
/// device) keeps the change as a pending target, which the next step builds
/// on, and is checked again 150 ms later; two such presses put that output in
/// pass-through until the output changes.
struct HUDKeyReducer: Sendable {
    static let verifyDelay: TimeInterval = 0.15
    static let standardStep = 1.0 / 16
    static let fineStep = 1.0 / 64
    /// A second timeout within this long removes the tap for good.
    static let timeoutWindow: TimeInterval = 10 * 60
    static let timeoutsToTrip = 2
    /// A callback slower than this is too slow to sit in the keyboard's path.
    static let slowCallback: TimeInterval = 0.05
    static let slowWindow: TimeInterval = 60
    static let slowCallbacksToTrip = 3
    /// Failures in a row before a kind of key is left to macOS.
    static let failuresToPass = 3

    enum Event: Equatable, Sendable {
        case keyDown(MediaKeyEvent), keyUp(MediaKeyEvent.Key)
        /// The result of an `.apply` effect.
        case applied(ApplyOutcome)
        case armed(Bool), visible(Bool), trust(Bool)
        case brightnessArmed(Bool)
        /// The output device (volume) or the display set (brightness) changed.
        case targetChanged(HUDKind)
        /// The wake asked for by an unconfirmed change.
        case verifyDue
        case verified(PendingTarget, reached: Bool)
        case tapDisabled(byTimeout: Bool, trusted: Bool)
        case callbackTook(TimeInterval)
    }

    enum Effect: Equatable, Sendable {
        /// Carry out the step, then feed back `.applied`.
        case apply(HUDStep, pending: PendingTarget?, skipping: Set<UInt32>)
        /// The verdict for the key being handled.
        case pass, swallow
        case show(HUDReading, modifiers: MediaKeyEvent.Modifiers)
        /// Feed back `.verifyDue` at this date.
        case wake(Date)
        /// Set the pending target once more, then feed back `.verified`.
        case reapply(PendingTarget)
        case reEnableTap, removeTap(HUDStopReason), latch(HUDStopReason)
    }

    private var armed = false
    private var visible = false
    private var trusted = false
    private var brightnessArmed = false
    /// The tap has been taken away. Final for this reducer: a new tap gets a new one.
    private var removed = false
    private var timeouts: [Date] = []
    private var slowCallbacks: [Date] = []
    private var failureStreak: [HUDKind: Int] = [:]
    /// Kinds of key left to macOS until their output changes.
    private var passThrough: Set<HUDKind> = []

    /// Counts presses (a down and its repeats), for counting unconfirmed ones.
    private var press = 0
    /// Per key, for the press in progress: whether every down so far was swallowed.
    private var swallowedAll: [MediaKeyEvent.Key: Bool] = [:]
    /// The down being applied, between `.apply` and `.applied`.
    private var inFlight: MediaKeyEvent?
    private var pending: [HUDKind: PendingTarget] = [:]
    private var pendingPress: [HUDKind: Int] = [:]
    private var skipping: [HUDKind: Set<UInt32>] = [:]
    private var unconfirmedPresses: [HUDKind: [UInt32: Set<Int>]] = [:]

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .keyDown(let key):
            return keyDown(key)
        case .keyUp(let key):
            return swallowedAll.removeValue(forKey: key) == true ? [.swallow] : [.pass]
        case .applied(let outcome):
            return applied(outcome, now: now)
        case .armed(let value):
            armed = value
        case .visible(let value):
            visible = value
        case .trust(let value):
            trusted = value
            if !value, armed, !removed { return remove(.permissionRevoked, latch: false) }
        case .brightnessArmed(let value):
            brightnessArmed = value
        case .targetChanged(let kind):
            pending[kind] = nil
            pendingPress[kind] = nil
            skipping[kind] = nil
            unconfirmedPresses[kind] = nil
            failureStreak[kind] = nil
            passThrough.remove(kind)
        case .verifyDue:
            return [HUDKind.volume, .brightness].compactMap { pending[$0] }.map { .reapply($0) }
        case .verified(let target, let reached):
            verified(target, reached: reached)
        case .tapDisabled(let byTimeout, let isTrusted):
            return tapDisabled(byTimeout: byTimeout, trusted: isTrusted, now: now)
        case .callbackTook(let seconds):
            return callbackTook(seconds, now: now)
        }
        return []
    }

    // MARK: Health

    /// macOS switched the tap off. Back on unless the permission is gone or
    /// the HUD isn't armed; a second timeout inside ten minutes ends it.
    private mutating func tapDisabled(byTimeout: Bool, trusted isTrusted: Bool, now: Date) -> [Effect] {
        guard armed, !removed else { return [] }
        guard isTrusted else {
            trusted = false
            return remove(.permissionRevoked, latch: false)
        }
        guard byTimeout else { return [.reEnableTap] }
        timeouts.removeAll { now.timeIntervalSince($0) > Self.timeoutWindow }
        timeouts.append(now)
        return timeouts.count >= Self.timeoutsToTrip ? remove(.timeouts, latch: true) : [.reEnableTap]
    }

    private mutating func callbackTook(_ seconds: TimeInterval, now: Date) -> [Effect] {
        guard armed, !removed, seconds > Self.slowCallback else { return [] }
        slowCallbacks.removeAll { now.timeIntervalSince($0) > Self.slowWindow }
        slowCallbacks.append(now)
        return slowCallbacks.count >= Self.slowCallbacksToTrip ? remove(.slowCallbacks, latch: true) : []
    }

    private mutating func remove(_ reason: HUDStopReason, latch: Bool) -> [Effect] {
        removed = true
        return latch ? [.removeTap(reason), .latch(reason)] : [.removeTap(reason)]
    }

    // MARK: Keys

    private mutating func keyDown(_ event: MediaKeyEvent) -> [Effect] {
        let key = event.key
        if event.isRepeat {
            // A repeat of a press whose first down we never saw: macOS has that press.
            guard swallowedAll[key] != nil else {
                swallowedAll[key] = false
                return [.pass]
            }
        } else {
            press += 1
            swallowedAll[key] = true
        }
        guard let step = step(for: event), !passThrough.contains(Self.kind(of: step)) else {
            swallowedAll[key] = false
            return [.pass]
        }
        inFlight = event
        let kind = Self.kind(of: step)
        return [.apply(step, pending: pending[kind], skipping: skipping[kind] ?? [])]
    }

    /// What the press asks for, or nil when it isn't ours to handle.
    private func step(for event: MediaKeyEvent) -> HUDStep? {
        guard armed, trusted, visible, !removed else { return nil }
        let modifiers = event.modifiers
        // Control and Command aren't ours; Option alone opens Sound or Displays settings.
        if !modifiers.isDisjoint(with: [.control, .command]) { return nil }
        if modifiers.contains(.option), !modifiers.contains(.shift) { return nil }
        let size = modifiers.contains(.option) ? Self.fineStep : Self.standardStep
        switch event.key {
        case .soundUp: return .level(.volume, delta: size)
        case .soundDown: return .level(.volume, delta: -size)
        case .mute: return .toggleMute
        case .brightnessUp: return brightnessArmed ? .level(.brightness, delta: size) : nil
        case .brightnessDown: return brightnessArmed ? .level(.brightness, delta: -size) : nil
        }
    }

    private static func kind(of step: HUDStep) -> HUDKind {
        switch step {
        case .level(let kind, _): kind
        case .toggleMute: .volume
        }
    }

    // MARK: Results

    private mutating func applied(_ outcome: ApplyOutcome, now: Date) -> [Effect] {
        guard let event = inFlight else { return [.pass] }
        inFlight = nil
        switch outcome {
        case .changed(let reading), .atLimit(let reading):
            failureStreak[reading.kind] = 0
            pending[reading.kind] = nil
            return [.swallow, .show(reading, modifiers: event.modifiers)]
        case .unconfirmed(let reading, let target):
            failureStreak[reading.kind] = 0
            pending[reading.kind] = target
            pendingPress[reading.kind] = press
            return [.swallow, .show(reading, modifiers: event.modifiers), .wake(now.addingTimeInterval(Self.verifyDelay))]
        case .failed(let kind):
            // CoreAudio or DisplayServices errors: after a few in a row, leave this kind to macOS.
            let streak = failureStreak[kind, default: 0] + 1
            failureStreak[kind] = streak
            if streak >= Self.failuresToPass { passThrough.insert(kind) }
            swallowedAll[event.key] = false
            return [.pass]
        case .notSettable, .skipped:
            swallowedAll[event.key] = false
            return [.pass]
        }
    }

    private mutating func verified(_ target: PendingTarget, reached: Bool) {
        let kind = target.kind
        // Either way the target has been checked: a newer one stays.
        if pending[kind] == target { pending[kind] = nil }
        guard !reached else { return }
        var presses = unconfirmedPresses[kind]?[target.targetID] ?? []
        presses.insert(pendingPress[kind] ?? press)
        unconfirmedPresses[kind, default: [:]][target.targetID] = presses
        if presses.count >= 2 { skipping[kind, default: []].insert(target.targetID) }
    }
}
