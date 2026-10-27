// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The user's choice of motion for the island (#72).
enum AnimationStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case snappy
    case smooth
    case bouncy

    var id: Self { self }

    var title: String {
        switch self {
        case .snappy: "Snappy"
        case .smooth: "Smooth"
        case .bouncy: "Bouncy"
        }
    }

    /// Spring parameters for expanding.
    var expandSpring: (response: Double, damping: Double) {
        switch self {
        case .snappy: (0.32, 0.86)
        case .smooth: (0.42, 0.78)
        case .bouncy: (0.48, 0.68)
        }
    }

    var expand: Animation {
        let spring = expandSpring
        return .spring(response: spring.response, dampingFraction: spring.damping)
    }

    /// Collapsing is a little faster and less bouncy than expanding.
    var collapse: Animation {
        let spring = expandSpring
        return .spring(response: spring.response * 0.85, dampingFraction: min(spring.damping + 0.1, 1))
    }
}

/// Shared motion tokens.
enum Motion {
    /// A tiny bounce when a new alert arrives.
    static let alertBounce = Animation.spring(response: 0.28, dampingFraction: 0.55)
    /// Used instead of springs when Reduce Motion is on: a quick, non-overshooting fade.
    static let reduced = Animation.easeInOut(duration: 0.18)

    /// Expanded content appears slightly after the shape starts growing and
    /// leaves quickly, so it never looks squashed during the morph.
    @MainActor static func expandedContent(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeInOut(duration: 0.15))
        }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .top))
                .combined(with: AnyTransition(.blurReplace))
                .animation(.smooth(duration: 0.32).delay(0.06)),
            removal: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .top))
                .animation(.easeOut(duration: 0.12))
        )
    }

    /// Short transition for content that swaps in place (compact slots, labels).
    @MainActor static var contentSwap: AnyTransition { .opacity.combined(with: .scale(scale: 0.9)) }

    /// How activity content animates when a module updates it. The island
    /// owns this timing (modules' own animations are dropped); Apple caps
    /// Live Activity content animations at 2 s.
    static let content = Animation.smooth(duration: 0.45)
    /// The expanded island growing or shrinking to fit new content.
    static let resize = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// Stale content dims until the module updates it.
    static let staleOpacity: Double = 0.55

    /// A minimal bubble budding off the island, or merging back: elastic,
    /// "a living organism" (WWDC23).
    static let budOff = Animation.spring(response: 0.5, dampingFraction: 0.7)

    /// A bubble emerges from under the island's edge, growing as it travels
    /// out to its place, and slips back under it to merge. With Reduce
    /// Motion it simply fades.
    @MainActor static func bud(fromLeading: Bool, distance: CGFloat, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        let offset = fromLeading ? -distance : distance
        return .modifier(
            active: BudEffect(offset: offset, scale: 0.55, anchor: fromLeading ? .leading : .trailing),
            identity: BudEffect(offset: 0, scale: 1, anchor: fromLeading ? .leading : .trailing)
        )
    }
}

/// The bud transition's geometry: slide in from the island's edge while growing.
struct BudEffect: ViewModifier {
    let offset: CGFloat
    let scale: CGFloat
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: anchor)
            .offset(x: offset)
    }
}
