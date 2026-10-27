// SPDX-License-Identifier: GPL-3.0-or-later

/// How the island's surface looks (#73). On notched displays the compact
/// island is always black so it merges with the hardware notch; the theme
/// fills the expanded island.
enum IslandTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case notchBlack
    case liquidGlass
    case tintedGlass

    var id: Self { self }

    var title: String {
        switch self {
        case .notchBlack: "Notch Black"
        case .liquidGlass: "Liquid Glass"
        case .tintedGlass: "Tinted Glass"
        }
    }

    var isGlass: Bool { self != .notchBlack }
}
