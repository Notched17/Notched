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
