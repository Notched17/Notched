// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The ranking class of a live activity, lowest first (ISLAND-BEHAVIOR.md §2).
/// A higher class wins the attached (primary) slot. Whatever is playing
/// stays primary over the user's own timers and tools (ADR-0011).
///
/// Foundation only, so the pure ranking rules can use it. Saved by `name`
/// (never by number), so reordering the cases can't reshuffle a user's
/// saved priority.
enum ActivityKind: Int, Comparable, CaseIterable, Sendable {
    /// Nice to know, e.g. charging, a weather alert.
    case passive
    /// Something the user started: a timer, keep-awake, a download, an agent working.
    case live
    /// Now Playing.
    case media
    /// Something the system is doing that the user must not miss: a call, screen recording.
    case system

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The stable name used in settings.
    var name: String {
        switch self {
        case .passive: "passive"
        case .live: "live"
        case .media: "media"
        case .system: "system"
        }
    }

    init?(name: String) {
        guard let kind = Self.allCases.first(where: { $0.name == name }) else { return nil }
        self = kind
    }
}

extension ActivityKind: Codable {
    init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let kind = ActivityKind(name: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown activity kind \(name)"))
        }
        self = kind
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}
