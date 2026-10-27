// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Turns a two-finger trackpad swipe (scroll-wheel events with gesture
/// phases) into one island gesture per swipe, in the direction the fingers
/// moved whatever the scrolling preference (ISLAND-BEHAVIOR.md §6). Pure, so
/// it is unit-tested; the island's views feed it `NSEvent`s.
///
/// Momentum after the fingers lift, and mouse wheels (no phases), never swipe.
struct SwipeRecognizer {
    enum Gesture: Equatable, Sendable {
        case left, right, up, down
    }

    enum Phase: Equatable, Sendable {
        case began, changed, ended, cancelled, momentum, none
    }

    struct Sample: Equatable, Sendable {
        /// `NSEvent.scrollingDeltaX` / `scrollingDeltaY`.
        var deltaX: CGFloat
        var deltaY: CGFloat
        var phase: Phase
        /// `NSEvent.isDirectionInvertedFromDevice` (natural scrolling).
        var isDirectionInverted: Bool
    }

    /// How far the fingers travel before a swipe counts.
    static let threshold: CGFloat = 28
    /// The swipe's direction must beat the other axis by this factor.
    static let dominance: CGFloat = 1.5

    private var travel = CGPoint.zero
    private var fired = false

    mutating func handle(_ sample: Sample) -> Gesture? {
        switch sample.phase {
        case .began:
            travel = .zero
            fired = false
            return nil
        case .ended, .cancelled, .momentum, .none:
            return nil
        case .changed:
            guard !fired else { return nil }
            // Finger movement: right and up are positive.
            let sign: CGFloat = sample.isDirectionInverted ? 1 : -1
            travel.x += sign * sample.deltaX
            travel.y -= sign * sample.deltaY
            let horizontal = abs(travel.x)
            let vertical = abs(travel.y)
            if horizontal >= Self.threshold, horizontal >= Self.dominance * vertical {
                fired = true
                return travel.x > 0 ? .right : .left
            }
            if vertical >= Self.threshold, vertical >= Self.dominance * horizontal {
                fired = true
                return travel.y > 0 ? .up : .down
            }
            return nil
        }
    }
}
