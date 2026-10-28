// SPDX-License-Identifier: GPL-3.0-or-later

/// Names a live activity; posting the same id again updates it in place.
struct ActivityID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var description: String { rawValue }
}

/// Names a module, e.g. "media". Stored in settings, so never rename one.
struct ModuleID: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var description: String { rawValue }
}
