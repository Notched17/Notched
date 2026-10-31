// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The colour picker's state (#55): the colour on show and the recent-colours
/// row. A new pick goes to the front, the same colour never appears twice,
/// and the row is capped. Nothing here touches the system; the shell samples
/// the screen and saves the row.
struct ColorPickerReducer: Sendable {
    static let recentLimit = 12

    struct State: Equatable, Sendable {
        /// The colour the panel shows. Nil until something is picked this session.
        var current: ColorValue?
        /// Set when the current colour had to be clamped into sRGB.
        var outsideGamut = false
        /// Newest first.
        var recents: [ColorValue] = []
    }

    enum Event: Equatable, Sendable {
        /// The saved row, read once at start.
        case loaded([ColorValue])
        case picked(ColorValue, outsideGamut: Bool)
        /// A swatch in the recent row was clicked.
        case selected(ColorValue)
        case clearRecents
    }

    enum Effect: Equatable, Sendable {
        /// Save this row.
        case persist([ColorValue])
    }

    private(set) var state = State()

    mutating func reduce(_ event: Event, now: Date) -> [Effect] {
        switch event {
        case .loaded(let saved):
            // Silent: what was saved earlier is not news, and nothing is on show yet.
            state.recents = Self.cleaned(saved)
            return []
        case .picked(let color, let outsideGamut):
            state.current = color
            state.outsideGamut = outsideGamut
            state.recents = Self.cleaned([color] + state.recents)
            return [.persist(state.recents)]
        case .selected(let color):
            // The row keeps its order, so it doesn't jump under the pointer.
            state.current = color
            state.outsideGamut = false
            return []
        case .clearRecents:
            guard !state.recents.isEmpty else { return [] }
            state.recents = []
            return [.persist([])]
        }
    }

    /// No repeats (the first, newest, wins) and at most `recentLimit`.
    private static func cleaned(_ colors: [ColorValue]) -> [ColorValue] {
        var seen = Set<ColorValue>()
        return Array(colors.filter { seen.insert($0).inserted }.prefix(recentLimit))
    }
}
