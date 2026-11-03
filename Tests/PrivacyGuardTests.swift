// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

/// A phone number, a face and a name were once committed in a test photo. These keep the
/// private test artefacts ignored so a careless `git add -A` can't publish them again.
@Suite("Privacy guard")
struct PrivacyGuardTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("The private test artefacts are in .gitignore")
    func ignored() throws {
        let ignore = try String(contentsOf: Self.repoRoot.appendingPathComponent(".gitignore"), encoding: .utf8)
        let lines = Set(ignore.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        for path in ["/docs/spikes/results/lockscreen-label.jpg", "/docs/prompts/M6-spike-1-assist.md", "/private/"] {
            #expect(lines.contains(path), "\(path) must stay in .gitignore")
        }
    }
}
