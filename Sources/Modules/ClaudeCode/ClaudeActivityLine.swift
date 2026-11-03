// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What Claude Code is doing right now, in a few words ("Editing session.ts"),
/// from the `PreToolUse` hook (#63). Only the tool's name and a short,
/// redacted target are kept: a file's name without its folders, the first
/// words of a command, a search pattern. Nothing else of the tool's input.
struct ClaudeActivityLine: Equatable, Sendable {
    /// "Editing", "Running", "Reading": short enough for beside the notch.
    var verb: String
    /// "session.ts", "npm run test": nil for a bare verb ("Planning").
    var target: String?

    var text: String { target.map { "\(verb) \($0)" } ?? verb }
}

enum ClaudeActivity {
    static let targetLimit = 40
    static let commandWords = 3

    static func line(toolName: String, input: [String: Any]) -> ClaudeActivityLine {
        switch toolName {
        case "Edit", "MultiEdit", "NotebookEdit":
            return ClaudeActivityLine(verb: "Editing", target: fileName(input["file_path"] ?? input["notebook_path"]))
        case "Write":
            return ClaudeActivityLine(verb: "Writing", target: fileName(input["file_path"]))
        case "Read":
            return ClaudeActivityLine(verb: "Reading", target: fileName(input["file_path"]))
        case "Bash":
            return ClaudeActivityLine(verb: "Running", target: command(input["command"]))
        case "Grep":
            return ClaudeActivityLine(verb: "Searching", target: (input["pattern"] as? String).flatMap { quoted($0) })
        case "Glob":
            return ClaudeActivityLine(verb: "Finding", target: clean(input["pattern"] as? String))
        case "WebFetch":
            return ClaudeActivityLine(verb: "Fetching", target: (input["url"] as? String).flatMap { URL(string: $0)?.host }.flatMap { clean($0) })
        case "WebSearch":
            return ClaudeActivityLine(verb: "Searching the web", target: nil)
        case "Task", "Agent":
            return ClaudeActivityLine(verb: "Running a subagent", target: nil)
        case "TodoWrite":
            return ClaudeActivityLine(verb: "Planning", target: nil)
        default:
            if toolName.hasPrefix("mcp__") {
                let parts = toolName.components(separatedBy: "__").filter { !$0.isEmpty }
                if parts.count >= 3 { return ClaudeActivityLine(verb: "Using", target: clean("\(parts[1]) › \(parts[2...].joined(separator: "__"))")) }
            }
            return ClaudeActivityLine(verb: "Using", target: clean(toolName))
        }
    }

    /// A file's own name, without its folders: enough to say what, and nothing about where.
    private static func fileName(_ path: Any?) -> String? {
        guard let path = path as? String, !path.isEmpty else { return nil }
        return clean(URL(fileURLWithPath: path).lastPathComponent)
    }

    /// The first few words of the command's first line, with secrets masked.
    private static func command(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let words = firstLine.split(whereSeparator: \.isWhitespace).prefix(commandWords).joined(separator: " ")
        return clean(SecretRedactor.redact(words))
    }

    private static func quoted(_ pattern: String) -> String? {
        clean(SecretRedactor.redact(pattern), limit: 24).map { "\u{201C}\($0)\u{201D}" }
    }

    /// One line: invisible and control characters out, redacted, clipped. Nil when nothing is left.
    private static func clean(_ text: String?, limit: Int = targetLimit) -> String? {
        guard let text else { return nil }
        let cleaned = ActivityPayload.sanitize(SecretRedactor.redact(text), limit: limit + 1)
        guard !cleaned.isEmpty else { return nil }
        return cleaned.count > limit ? String(cleaned.prefix(limit - 1)) + "…" : cleaned
    }
}
