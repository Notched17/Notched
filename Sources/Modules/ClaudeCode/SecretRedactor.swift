// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Hides anything that looks like a secret in text the island displays (a
/// command Claude Code wants to run). Display only: the real request goes to
/// Claude Code untouched. Errs on the side of hiding.
enum SecretRedactor {
    static let mask = "••••"

    private struct Rule {
        let regex: NSRegularExpression
        let template: String
    }

    private static let rules: [Rule] = {
        let table: [(String, String)] = [
            // Private key blocks, even when cut off.
            (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)"#, mask),
            // Well-known token formats.
            (#"\b(?:sk-ant-[A-Za-z0-9_\-]{8,}|sk-[A-Za-z0-9_\-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_\-]{30,}|eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,})"#, mask),
            // "Bearer xyz" and "Authorization: Basic xyz".
            (#"(?i)(bearer\s+)[A-Za-z0-9._~+/\-=]{8,}"#, "$1" + mask),
            (#"(?i)(authorization:\s*)(?:\w+\s+)?[^\s'"]+"#, "$1" + mask),
            // --password=x, --token x, --api-key=x
            (#"(?i)(--?(?:password|passwd|pass|token|secret|api[-_]?key)(?:=|\s+))[^\s'"]+"#, "$1" + mask),
            // FOO_TOKEN=x, "API_KEY='x'"
            (#"(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|PRIVATE_KEY|CREDENTIALS?)[A-Z0-9_]*)=("[^"]*"|'[^']*'|\S+)"#, "$1=" + mask),
            // scheme://user:password@host
            (#"(://[^/\s:@]+:)[^@\s/]+(@)"#, "$1" + mask + "$2"),
        ]
        return table.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { Rule(regex: $0, template: template) }
        }
    }()

    private static let longRun = try? NSRegularExpression(pattern: #"[A-Za-z0-9_\-]{32,}"#)

    static func redact(_ text: String) -> String {
        var result = text
        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = rule.regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return redactLongRuns(result)
    }

    /// A run of 32+ letters, digits, dashes and underscores that mixes letters
    /// and digits is probably a key; plain words and paths aren't touched.
    private static func redactLongRuns(_ text: String) -> String {
        guard let longRun else { return text }
        var result = text
        let matches = longRun.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let run = result[range]
            if run.contains(where: \.isNumber), run.contains(where: \.isLetter) {
                result.replaceSubrange(range, with: mask)
            }
        }
        return result
    }
}
