// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ActivityID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var description: String { rawValue }
}

struct ModuleID: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var description: String { rawValue }
}

/// How important an activity is. Higher wins the compact island (#8).
enum ActivityPriority: Int, Comparable, Sendable {
    case idle = 0
    case media = 100
    case liveSession = 200
    case alert = 300

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Whether an activity lasts until removed or disappears on its own.
enum ActivityLifetime: Equatable, Sendable {
    case untilRemoved
    case transient(Duration)
}

/// A piece of island UI supplied by a module.
@MainActor
struct ActivityContent {
    /// The width this content needs in a compact slot.
    let width: CGFloat
    let accessibilityLabel: String
    let view: () -> AnyView

    init<Content: View>(width: CGFloat, accessibilityLabel: String, @ViewBuilder _ view: @escaping () -> Content) {
        self.width = width
        self.accessibilityLabel = accessibilityLabel
        self.view = { AnyView(view()) }
    }
}

/// Something live that a module wants the island to show.
@MainActor
struct Activity: Identifiable {
    let id: ActivityID
    let moduleID: ModuleID
    var priority: ActivityPriority
    var lifetime: ActivityLifetime
    var compactLeading: ActivityContent?
    var compactTrailing: ActivityContent?
    var expanded: ActivityContent?
}
