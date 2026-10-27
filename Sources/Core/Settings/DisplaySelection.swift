// SPDX-License-Identifier: GPL-3.0-or-later

/// What the display-selection rule needs to know about a connected screen.
struct DisplayCandidate: Equatable, Sendable {
    let id: DisplayID
    let isBuiltIn: Bool
    let hasNotch: Bool
}

/// Which displays show an island.
enum DisplaySelection: Hashable, Sendable, Codable {
    /// The built-in notched display when it's on, otherwise the primary display.
    case main
    case all
    /// One display; falls back to `.main` while it's disconnected.
    case specific(DisplayID)

    /// The displays that should show an island. `candidates` must be in
    /// `NSScreen.screens` order, so the first one is the primary display.
    func resolve(among candidates: [DisplayCandidate]) -> [DisplayID] {
        switch self {
        case .all:
            return candidates.map(\.id)
        case .specific(let id) where candidates.contains(where: { $0.id == id }):
            return [id]
        case .main, .specific:
            let preferred = candidates.first { $0.isBuiltIn && $0.hasNotch } ?? candidates.first
            return preferred.map { [$0.id] } ?? []
        }
    }
}
