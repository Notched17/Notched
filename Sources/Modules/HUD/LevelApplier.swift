// SPDX-License-Identifier: GPL-3.0-or-later

/// Carries out one key press against an output (the safety design's §3.2–3.3):
/// takes an absolute target on a 1/16 (or 1/64) grid, sets it, reads it back,
/// and says whether the change took effect. Pure apart from the controls it
/// is handed.
enum LevelApplier {
    /// A read-back this close to the target reached it.
    private static let reachedTolerance = 0.002
    /// A read-back that moved at least this far towards it counts too
    /// (hardware that rounds to its own steps).
    private static let movedEnough = 0.001

    /// The next level: from the pending target if there is one, else from
    /// what was read, rounded onto the grid of `1 / |delta|` steps and clamped.
    static func target(current: Double, pending: Double?, delta: Double) -> Double {
        let steps = 1 / abs(delta)
        let raw = (pending ?? current) + delta
        return min(1, max(0, (raw * steps).rounded() / steps))
    }

    static func apply(_ step: HUDStep, pending: PendingTarget?, skipping: Set<UInt32>,
                      levels: some LevelControl, mute: (any MuteControl)?) -> ApplyOutcome {
        switch step {
        case let .level(kind, delta):
            return adjust(kind, delta: delta, pending: pending, skipping: skipping, levels: levels, mute: mute)
        case .toggleMute:
            return toggleMute(skipping: skipping, levels: levels, mute: mute)
        }
    }

    /// Sets a pending target once more, for the check that follows an
    /// unconfirmed change. True once the read-back reached it. Never touches
    /// an output other than the one it was set on.
    static func reapply(_ pending: PendingTarget, levels: some LevelControl) -> Bool {
        guard levels.currentTarget() == pending.targetID,
              levels.setLevel(pending.level, on: pending.targetID),
              let readBack = levels.level(pending.targetID) else { return false }
        return abs(readBack - pending.level) <= reachedTolerance
    }

    // MARK: Steps

    private static func adjust(_ kind: HUDKind, delta: Double, pending: PendingTarget?, skipping: Set<UInt32>,
                               levels: some LevelControl, mute: (any MuteControl)?) -> ApplyOutcome {
        guard let id = levels.currentTarget() else { return .failed(kind) }
        if skipping.contains(id) { return .skipped(kind) }
        guard levels.isSettable(id) else { return .notSettable(kind) }
        guard let current = levels.level(id) else { return .failed(kind) }

        let pendingLevel = pending.flatMap { $0.kind == kind && $0.targetID == id ? $0.level : nil }
        let base = pendingLevel ?? current
        let goal = target(current: current, pending: pendingLevel, delta: delta)

        if goal == base, base <= 0 || base >= 1 {
            let isMuted = settleMute(for: goal, kind: kind, id: id, mute: mute)
            return .atLimit(HUDReading(kind: kind, targetID: id, level: base, isMuted: isMuted, atLimit: true))
        }

        guard levels.setLevel(goal, on: id) else { return .failed(kind) }
        let isMuted = settleMute(for: goal, kind: kind, id: id, mute: mute)
        let reading = HUDReading(kind: kind, targetID: id, level: goal, isMuted: isMuted, atLimit: false)
        let unconfirmed = ApplyOutcome.unconfirmed(reading, PendingTarget(kind: kind, targetID: id, level: goal))
        guard let readBack = levels.level(id) else { return unconfirmed }
        return reached(readBack, goal: goal, from: current) ? .changed(reading) : unconfirmed
    }

    private static func toggleMute(skipping: Set<UInt32>, levels: some LevelControl,
                                   mute: (any MuteControl)?) -> ApplyOutcome {
        guard let mute, let id = levels.currentTarget() else { return .failed(.volume) }
        if skipping.contains(id) { return .skipped(.volume) }
        guard let wasMuted = mute.isMuted(id),
              mute.setMuted(!wasMuted, on: id),
              mute.isMuted(id) == !wasMuted else { return .failed(.volume) }
        let level = levels.level(id) ?? 0
        return .changed(HUDReading(kind: .volume, targetID: id, level: level, isMuted: !wasMuted, atLimit: false))
    }

    /// As macOS does: any audible level unmutes, and 0 mutes. Only volume has
    /// a mute. Returns the mute state afterwards.
    private static func settleMute(for goal: Double, kind: HUDKind, id: UInt32, mute: (any MuteControl)?) -> Bool {
        guard kind == .volume, let mute, let isMuted = mute.isMuted(id) else { return false }
        let wantMuted = goal <= 0
        if isMuted != wantMuted, mute.setMuted(wantMuted, on: id) { return wantMuted }
        return isMuted
    }

    private static func reached(_ readBack: Double, goal: Double, from start: Double) -> Bool {
        if abs(readBack - goal) <= reachedTolerance { return true }
        return (readBack - start) * (goal - start) > 0 && abs(readBack - start) >= movedEnough
    }
}
