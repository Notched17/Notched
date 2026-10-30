// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A line diff for the "what will change" preview. Pure.
enum LineDiff {
    struct Line: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable { case same, added, removed, gap }
        let id: Int
        var kind: Kind
        var text: String
    }

    /// The changed lines with `context` unchanged lines around them; longer
    /// unchanged stretches become a single gap line.
    static func diff(old: String, new: String, context: Int = 2) -> [Line] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let all = full(a, b)
        guard all.contains(where: { $0.kind != .same }) else { return [] }

        var keep = [Bool](repeating: false, count: all.count)
        for (index, line) in all.enumerated() where line.kind != .same {
            for near in max(0, index - context)...min(all.count - 1, index + context) { keep[near] = true }
        }
        var result: [Line] = []
        var skipped = false
        for (index, line) in all.enumerated() {
            if keep[index] {
                if skipped { result.append(Line(id: result.count, kind: .gap, text: "…")); skipped = false }
                result.append(Line(id: result.count, kind: line.kind, text: line.text))
            } else {
                skipped = true
            }
        }
        return result
    }

    private static func full(_ a: [String], _ b: [String]) -> [Line] {
        // Beyond this size an exact diff isn't worth the memory; show a replacement.
        guard a.count * b.count <= 4_000_000 else {
            return a.map { Line(id: 0, kind: .removed, text: $0) } + b.map { Line(id: 0, kind: .added, text: $0) }
        }
        let n = a.count, m = b.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var lines: [Line] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                lines.append(Line(id: 0, kind: .same, text: a[i])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                lines.append(Line(id: 0, kind: .removed, text: a[i])); i += 1
            } else {
                lines.append(Line(id: 0, kind: .added, text: b[j])); j += 1
            }
        }
        while i < n { lines.append(Line(id: 0, kind: .removed, text: a[i])); i += 1 }
        while j < m { lines.append(Line(id: 0, kind: .added, text: b[j])); j += 1 }
        return lines
    }
}
