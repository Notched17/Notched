// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The view for one named region of an activity. The island decides where
/// the region goes, how big it is and how it animates (ISLAND-BEHAVIOR.md §4–5);
/// a module only supplies what's inside.
@MainActor
struct IslandRegion {
    let view: () -> AnyView

    init<Content: View>(@ViewBuilder _ view: @escaping () -> Content) {
        self.view = { AnyView(view()) }
    }
}

/// A region of the expanded presentation.
@MainActor
struct ExpandedRegion {
    enum Placement: Sendable {
        /// Beside the camera housing, wrapping below it if tall.
        case besideHousing
        /// Below the camera housing if it doesn't fit beside it (leading only).
        case belowIfTooWide
    }

    /// The region with the highest priority renders at the island's full width.
    var priority: Double
    var placement: Placement
    let view: () -> AnyView

    init<Content: View>(priority: Double = 0, placement: Placement = .besideHousing, @ViewBuilder _ view: @escaping () -> Content) {
        self.priority = priority
        self.placement = placement
        self.view = { AnyView(view()) }
    }
}

/// The expanded presentation's regions, laid out like WidgetKit's
/// `DynamicIslandExpandedRegion`s: leading and trailing beside the camera
/// housing, center below it, bottom across the full width.
@MainActor
struct ExpandedPresentation {
    var leading: ExpandedRegion?
    var trailing: ExpandedRegion?
    var center: ExpandedRegion?
    var bottom: ExpandedRegion?

    init(leading: ExpandedRegion? = nil, trailing: ExpandedRegion? = nil, center: ExpandedRegion? = nil, bottom: ExpandedRegion? = nil) {
        self.leading = leading
        self.trailing = trailing
        self.center = center
        self.bottom = bottom
    }
}

/// Everything an activity can look like, by presentation.
@MainActor
struct ActivityPresentation {
    /// Left of the notch. Medium weight or heavier; one glyph or a short value.
    var compactLeading: IslandRegion
    /// Right of the notch. Nil hides the trailing side.
    var compactTrailing: IslandRegion?
    /// A detached bubble when several activities run. Live data (a countdown,
    /// a progress ring), not just a logo; it must fit a 28 pt circle.
    var minimal: IslandRegion
    var expanded: ExpandedPresentation

    init(compactLeading: IslandRegion, compactTrailing: IslandRegion? = nil, minimal: IslandRegion, expanded: ExpandedPresentation) {
        self.compactLeading = compactLeading
        self.compactTrailing = compactTrailing
        self.minimal = minimal
        self.expanded = expanded
    }
}

/// A short system event shown as a wide compact banner: charging, Caps Lock,
/// a device connecting. It pre-empts the compact island for a moment, then
/// the island returns to what it showed. It never takes a minimal slot.
@MainActor
struct TransientBanner: Identifiable {
    /// Showing a banner with the same id again replaces it and restarts its
    /// time, so repeated key presses keep one banner up.
    let id: String
    let moduleID: ModuleID
    var leading: IslandRegion
    var trailing: IslandRegion?
    /// How long it shows; nil uses the user's setting.
    var duration: Duration?
    var accessibilityLabel: String

    init(id: String, moduleID: ModuleID, leading: IslandRegion, trailing: IslandRegion? = nil,
         duration: Duration? = nil, accessibilityLabel: String) {
        self.id = id
        self.moduleID = moduleID
        self.leading = leading
        self.trailing = trailing
        self.duration = duration
        self.accessibilityLabel = accessibilityLabel
    }
}
