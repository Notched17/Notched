// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

/// Source-level guards from the M6 accessibility audit (docs/ACCESSIBILITY.md).
/// They read the Swift files, so a regression is caught by `scripts/test.sh`.
@Suite("Accessibility lint")
struct AccessibilityLintTests {
    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
    }

    private static func swiftFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" && !$0.path.contains("/Debug/") }
    }

    @Test("Text on the black island is never dimmer than 55 % white (4.5:1 contrast)")
    func noDimText() throws {
        let pattern = try Regex(#"foregroundStyle\(\.white\.opacity\(0\.(\d+)\)\)"#)
        var offenders: [String] = []
        for file in Self.swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: pattern) {
                guard let digits = match.output[1].substring, let value = Double("0." + digits) else { continue }
                if value < 0.55 { offenders.append("\(file.lastPathComponent): white.opacity(\(value))") }
            }
        }
        #expect(offenders.isEmpty, "Too dim for small text on black: \(offenders)")
    }

    @Test("Every blurReplace transition falls back to a plain fade under Reduce Motion")
    func blurTransitionsRespectReduceMotion() throws {
        var offenders: [String] = []
        for file in Self.swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains(".transition(AnyTransition(.blurReplace)") && !line.contains("reduceMotion") {
                offenders.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, "Gate on reduceMotion: \(offenders)")
    }
}
