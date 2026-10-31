// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Rankings are saved by name, so reordering the enum can never reshuffle a
/// user's saved priority.
@Suite("ActivityKind")
struct ActivityKindTests {
    @Test("Every kind has a stable name that round-trips")
    func namesRoundTrip() {
        #expect(ActivityKind.allCases.map(\.name) == ["passive", "live", "media", "system"])
        for kind in ActivityKind.allCases { #expect(ActivityKind(name: kind.name) == kind) }
        #expect(ActivityKind(name: "nonsense") == nil)
    }

    @Test("Codable uses the name, not the number")
    func codableUsesName() throws {
        let data = try JSONEncoder().encode([ActivityKind.media, .live])
        #expect(String(decoding: data, as: UTF8.self) == "[\"media\",\"live\"]")
        #expect(try JSONDecoder().decode([ActivityKind].self, from: data) == [.media, .live])
    }

    @Test("An unknown name fails to decode instead of becoming some other kind")
    func unknownNameFails() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode([ActivityKind].self, from: Data("[\"bogus\"]".utf8)) }
    }
}
