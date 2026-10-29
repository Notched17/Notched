// SPDX-License-Identifier: GPL-3.0-or-later

/// The four looks of the HUD (#23). Every one is a banner in the compact
/// island, so it pre-empts what's showing and then the island returns to it.
enum HUDStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The glyph on one side of the notch, a level bar and the output's icon on the other.
    case inline
    /// A tall slim bar that fills upwards.
    case vertical
    /// The glyph inside a ring that fills round.
    case circular
    /// The glyph and a hairline bar, nothing else.
    case minimal

    var id: Self { self }

    var title: String {
        switch self {
        case .inline: "Inline"
        case .vertical: "Vertical"
        case .circular: "Circular"
        case .minimal: "Minimal"
        }
    }
}
