// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Synchronization

/// What the tap does with the event it is looking at.
enum TapVerdict: Sendable, Equatable {
    case pass, swallow
}

/// What the tap does about its own health, right inside the callback.
enum TapHealthAction: Sendable, Equatable {
    case none
    case reEnable
    case remove(HUDStopReason)
}

/// `HUDKeyReducer` behind a lock, with the system on its other side: it feeds
/// the reducer, carries out the `.apply` and `.reapply` effects against the
/// real controls, and hands everything else (`.show`, `.wake`, `.latch`,
/// `.removeTap`) to `deliver`.
///
/// Called from the tap's thread for keys and from the main actor for state
/// (armed, visible, trust, output changes). The lock is never held while an
/// output is adjusted, so a slow device can't block main, and a control that
/// calls back into the engine can't deadlock it.
final class HUDKeyEngine: Sendable {
    private let state = Mutex(HUDKeyReducer())
    private let volume: any LevelControl & MuteControl
    private let brightness: (any LevelControl)?
    private let now: @Sendable () -> Date
    private let deliver: @Sendable ([HUDKeyReducer.Effect]) -> Void

    /// - Parameter deliver: runs on whichever thread produced the effects (the
    ///   tap's, for a key); it must not block, and hops to the main actor itself.
    init(volume: any LevelControl & MuteControl, brightness: (any LevelControl)?,
         now: @escaping @Sendable () -> Date = Date.init,
         deliver: @escaping @Sendable ([HUDKeyReducer.Effect]) -> Void) {
        self.volume = volume
        self.brightness = brightness
        self.now = now
        self.deliver = deliver
    }

    /// One key event, on the tap thread. Applies the change synchronously and
    /// returns the verdict for the event.
    func handle(_ event: MediaKeyEvent) -> TapVerdict {
        let reducerEvent: HUDKeyReducer.Event = event.phase == .down ? .keyDown(event) : .keyUp(event.key)
        return run(reducerEvent) ?? .pass
    }

    /// State from the main actor: armed, visible, trust, brightness armed,
    /// target changes, and the wake for an unconfirmed change.
    func send(_ event: HUDKeyReducer.Event) {
        _ = run(event)
    }

    /// The system switched the tap off.
    func tapDisabled(byTimeout: Bool, trusted: Bool) -> TapHealthAction {
        health(.tapDisabled(byTimeout: byTimeout, trusted: trusted))
    }

    /// How long the callback took for one event.
    func callbackTook(_ seconds: TimeInterval) -> TapHealthAction {
        health(.callbackTook(seconds))
    }

    // MARK: Running effects

    private func reduce(_ event: HUDKeyReducer.Event) -> [HUDKeyReducer.Effect] {
        state.withLock { $0.reduce(event, now: now()) }
    }

    private func health(_ event: HUDKeyReducer.Event) -> TapHealthAction {
        let effects = reduce(event)
        let outbound = effects.filter { $0 != .reEnableTap }
        if !outbound.isEmpty { deliver(outbound) }
        for effect in effects {
            switch effect {
            case .reEnableTap: return .reEnable
            case .removeTap(let reason): return .remove(reason)
            default: continue
            }
        }
        return .none
    }

    /// Feeds one event in and works through what comes out, feeding the
    /// results of `.apply` and `.reapply` back in. The last pass or swallow wins.
    private func run(_ event: HUDKeyReducer.Event) -> TapVerdict? {
        var verdict: TapVerdict?
        var outbound: [HUDKeyReducer.Effect] = []
        var queue = reduce(event)
        while !queue.isEmpty {
            switch queue.removeFirst() {
            case .pass:
                verdict = .pass
            case .swallow:
                verdict = .swallow
            case .apply(let step, let pending, let skipping):
                queue.insert(contentsOf: reduce(.applied(outcome(of: step, pending: pending, skipping: skipping))), at: 0)
            case .reapply(let target):
                let reached = reapply(target)
                queue.insert(contentsOf: reduce(.verified(target, reached: reached)), at: 0)
            case let other:
                outbound.append(other)
            }
        }
        if !outbound.isEmpty { deliver(outbound) }
        return verdict
    }

    private func outcome(of step: HUDStep, pending: PendingTarget?, skipping: Set<UInt32>) -> ApplyOutcome {
        if case .level(.brightness, _) = step {
            // No display control means macOS handles brightness.
            guard let brightness else { return .failed(.brightness) }
            return LevelApplier.apply(step, pending: pending, skipping: skipping, levels: brightness, mute: nil)
        }
        return LevelApplier.apply(step, pending: pending, skipping: skipping, levels: volume, mute: volume)
    }

    private func reapply(_ target: PendingTarget) -> Bool {
        switch target.kind {
        case .volume: LevelApplier.reapply(target, levels: volume)
        case .brightness: brightness.map { LevelApplier.reapply(target, levels: $0) } ?? false
        }
    }
}
