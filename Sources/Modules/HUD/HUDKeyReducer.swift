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
        case .brightnessArmed(let value):
            brightnessArmed = value
        case .targetChanged(let kind):
            pending[kind] = nil
            pendingPress[kind] = nil
            skipping[kind] = nil
            unconfirmedPresses[kind] = nil
        case .verifyDue:
            return [HUDKind.volume, .brightness].compactMap { pending[$0] }.map { .reapply($0) }
        case .verified(let target, let reached):
            verified(target, reached: reached)
        case .tapDisabled, .callbackTook:
            break
        }
        return []
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
        guard let step = step(for: event) else {
            swallowedAll[key] = false
            return [.pass]
        }
        inFlight = event
        let kind = Self.kind(of: step)
        return [.apply(step, pending: pending[kind], skipping: skipping[kind] ?? [])]
    }

    /// What the press asks for, or nil when it isn't ours to handle.
    private func step(for event: MediaKeyEvent) -> HUDStep? {
        guard armed, trusted, visible else { return nil }
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
            pending[reading.kind] = nil
            return [.swallow, .show(reading, modifiers: event.modifiers)]
        case .unconfirmed(let reading, let target):
            pending[reading.kind] = target
            pendingPress[reading.kind] = press
            return [.swallow, .show(reading, modifiers: event.modifiers), .wake(now.addingTimeInterval(Self.verifyDelay))]
        case .notSettable, .failed, .skipped:
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
