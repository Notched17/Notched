// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One safe line describing what a tool wants to do, for the approval card:
/// the command or path, relative to the project, redacted and truncated.
enum ToolRequestSummary {
    static let limit = 160

    static func detail(toolName: String, input: [String: Any], cwd: String, home: String) -> String {
        let raw: String
        switch toolName {
        case "Bash":
            raw = string(input["command"]) ?? toolName
        case "Edit", "Write", "Read", "NotebookEdit", "MultiEdit":
            raw = (string(input["file_path"]) ?? string(input["notebook_path"])).map { relativePath($0, cwd: cwd, home: home) } ?? toolName
        case "Glob", "Grep":
            raw = [string(input["pattern"]), string(input["path"]).map { "in " + relativePath($0, cwd: cwd, home: home) }]
                .compactMap { $0 }.joined(separator: " ")
        case "WebFetch":
            raw = string(input["url"]).map(hostAndPath) ?? toolName
        case "WebSearch":
            raw = string(input["query"]) ?? toolName
        default:
            if toolName.hasPrefix("mcp__") {
                // mcp__server__tool
                let parts = toolName.components(separatedBy: "__").filter { !$0.isEmpty }
                raw = parts.count >= 3 ? "\(parts[1]) › \(parts[2...].joined(separator: "__"))" : toolName
            } else {
                raw = input.keys.sorted().compactMap { string(input[$0]) }.first ?? toolName
            }
        }
        return fit(SecretRedactor.redact(raw))
    }

    /// How many lines of a change the card shows.
    static let maxChangeLines = 5
    static let maxChangeLineLength = 60

    /// The changed lines of an Edit (or the first edit of a MultiEdit), for the
    /// approval card: redacted, control characters out, clipped, at most
    /// `maxChangeLines` (the rest becomes "…"). Empty for any other tool.
    static func changes(toolName: String, input: [String: Any]) -> [LineDiff.Line] {
        var old: String?
        var new: String?
        var otherEdits = 0
        switch toolName {
        case "Edit":
            old = input["old_string"] as? String
            new = input["new_string"] as? String
        case "MultiEdit":
            let edits = input["edits"] as? [[String: Any]]
            old = edits?.first?["old_string"] as? String
            new = edits?.first?["new_string"] as? String
            otherEdits = max((edits?.count ?? 1) - 1, 0)
        default:
            return []
        }
        guard let old, let new, old != new else { return [] }
        let lines = LineDiff.diff(old: SecretRedactor.redact(old), new: SecretRedactor.redact(new), context: 1)
        var result = lines.prefix(maxChangeLines).enumerated().map { index, line in
            LineDiff.Line(id: index, kind: line.kind, text: clip(line.text))
        }
        if lines.count > maxChangeLines { result.append(LineDiff.Line(id: result.count, kind: .gap, text: "…")) }
        // Nothing may be left off the card without saying so: the other edits of a MultiEdit.
        if otherEdits > 0 {
            result.append(LineDiff.Line(id: result.count, kind: .gap, text: "+\(otherEdits) more edit\(otherEdits == 1 ? "" : "s") not shown"))
        }
        return result
    }

    /// One display line: tabs become two spaces; control, bidirectional, zero-width
    /// and other invisible characters go (the same ones `ActivityPayload.sanitize`
    /// drops, so a hidden character can't disguise what the card shows); long lines are clipped.
    static func clip(_ line: String) -> String {
        let cleaned = String(String.UnicodeScalarView(line.unicodeScalars.flatMap { scalar -> [Unicode.Scalar] in
            if scalar == "\t" { return [" ", " "] }
            return isInvisible(scalar) ? [] : [scalar]
        }))
        guard cleaned.count > maxChangeLineLength else { return cleaned }
        return String(cleaned.prefix(maxChangeLineLength - 1)) + "…"
    }

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x206F, 0xFEFF, 0xFFF9...0xFFFB:
            return true
        default:
            switch scalar.properties.generalCategory {
            case .format, .lineSeparator, .paragraphSeparator, .control: return true
            default: return false
            }
        }
    }

    /// Display text: control characters out, one line, middle-truncated.
    static func fit(_ text: String) -> String {
        let flat = ActivityPayload.sanitize(text, limit: 2000)
        guard flat.count > limit else { return flat }
        let head = flat.prefix(limit * 2 / 3)
        let tail = flat.suffix(limit - head.count - 1)
        return head + "…" + tail
    }

    static func relativePath(_ path: String, cwd: String, home: String) -> String {
        if !cwd.isEmpty, path == cwd { return "." }
        if !cwd.isEmpty, path.hasPrefix(cwd + "/") { return String(path.dropFirst(cwd.count + 1)) }
        if !home.isEmpty, path == home { return "~" }
        if !home.isEmpty, path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return path
    }

    private static func hostAndPath(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        return host + url.path
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}
