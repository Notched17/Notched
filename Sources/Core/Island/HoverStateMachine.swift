// SPDX-License-Identifier: GPL-3.0-or-later

/// Decides when the island expands and collapses in response to the pointer.
///
/// Pure and synchronous: it returns effects (start or cancel a timer, expand,
/// collapse) and the controller carries them out, feeding timer expiries back
/// in as events.
struct HoverStateMachine: Sendable {
    enum State: Equatable, Sendable {
        case compact
        case pendingExpand
        case expanded
        case pendingCollapse
    }

    enum Event: Equatable, Sendable {
        case pointerEntered
        case pointerExited
        case clicked
        case expandDelayElapsed
        case collapseGraceElapsed
        /// Collapse now, e.g. after a button in the island opened a window.
        case forceCollapse
        /// Expand without the pointer, e.g. a debug command.
        case forceExpand
    }

    enum ExpandReason: Equatable, Sendable {
        case hover
        case click
        case programmatic
    }

    enum Effect: Equatable, Sendable {
        case scheduleExpand(after: Duration)
        case scheduleCollapse(after: Duration)
        case cancelTimers
        case expand(ExpandReason)
        case collapse
    }

    /// How long the pointer may be away before the island collapses, so a
    /// slightly overshooting pointer doesn't make it flicker.
    static let collapseGrace = Duration.milliseconds(200)

    private(set) var state: State

    init(state: State = .compact) {
        self.state = state
    }

    mutating func handle(_ event: Event, hoverEnabled: Bool, hoverDelay: Duration) -> [Effect] {
        switch (state, event) {
        case (.compact, .pointerEntered):
            guard hoverEnabled else { return [] }
            if hoverDelay <= .zero {
                state = .expanded
                return [.expand(.hover)]
            }
            state = .pendingExpand
            return [.scheduleExpand(after: hoverDelay)]

        case (.pendingExpand, .expandDelayElapsed):
            state = .expanded
            return [.expand(.hover)]

        case (.pendingExpand, .pointerExited):
            state = .compact
            return [.cancelTimers]

        case (.compact, .clicked), (.pendingExpand, .clicked):
            state = .expanded
            return [.cancelTimers, .expand(.click)]

        case (.expanded, .pointerExited):
            state = .pendingCollapse
            return [.scheduleCollapse(after: Self.collapseGrace)]

        case (.pendingCollapse, .pointerEntered):
            state = .expanded
            return [.cancelTimers]

        case (.pendingCollapse, .collapseGraceElapsed):
            state = .compact
            return [.collapse]

        case (.expanded, .forceCollapse), (.pendingCollapse, .forceCollapse):
            state = .compact
            return [.cancelTimers, .collapse]

        case (.compact, .forceCollapse), (.pendingExpand, .forceCollapse):
            state = .compact
            return [.cancelTimers]

        case (.compact, .forceExpand), (.pendingExpand, .forceExpand):
            state = .expanded
            return [.cancelTimers, .expand(.programmatic)]

        case (.pendingCollapse, .forceExpand):
            state = .expanded
            return [.cancelTimers]

        default:
            // Clicks inside the expanded island belong to its content, and
            // timer events that arrive after the state moved on are stale.
            return []
        }
    }
}
