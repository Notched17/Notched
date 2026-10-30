// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The "Always allow" rule Claude Code offered with a permission request.
struct AlwaysAllowSuggestion: Equatable, Sendable {
    /// The suggestion object exactly as Claude Code sent it, to echo back.
    var json: Data
    /// A short label such as "Bash(npm test)".
    var label: String
}

/// A hook call from Claude Code, reduced to what the island needs
/// (https://code.claude.com/docs/en/hooks). Everything displayed is already
/// redacted and truncated, so the rest of the app never holds a raw command.
struct ClaudeHookEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case sessionStart
        case userPromptSubmit
        case permissionRequest
        case notification(type: String)
        case stop
        case stopFailure(error: String)
        case sessionEnd(reason: String)
        case other(String)
    }

    var kind: Kind
    var sessionID: String
    var cwd: String
    var project: String
    var title: String?
    var toolName: String?
    var detail: String?
    var suggestion: AlwaysAllowSuggestion?

    static let maxBodyBytes = 256 * 1024

    /// Nil if the body isn't a hook payload we can use.
    static func parse(_ data: Data, home: String = NSHomeDirectory()) -> ClaudeHookEvent? {
        guard data.count <= maxBodyBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any],
              let name = json["hook_event_name"] as? String,
              let rawSession = json["session_id"] as? String else { return nil }
        let sessionID = ActivityPayload.sanitize(rawSession, limit: 80)
        guard !sessionID.isEmpty else { return nil }
        let cwd = (json["cwd"] as? String) ?? ""
        let project = ActivityPayload.sanitize(URL(fileURLWithPath: cwd).lastPathComponent, limit: 40)

        let kind: Kind
        switch name {
        case "SessionStart": kind = .sessionStart
        case "UserPromptSubmit": kind = .userPromptSubmit
        case "PermissionRequest": kind = .permissionRequest
        case "Notification": kind = .notification(type: (json["notification_type"] as? String) ?? "")
        case "Stop": kind = .stop
        case "StopFailure": kind = .stopFailure(error: ActivityPayload.sanitize((json["error"] as? String) ?? "unknown", limit: 40))
        case "SessionEnd": kind = .sessionEnd(reason: ActivityPayload.sanitize((json["reason"] as? String) ?? "", limit: 40))
        default: kind = .other(ActivityPayload.sanitize(name, limit: 40))
        }

        var event = ClaudeHookEvent(kind: kind, sessionID: sessionID, cwd: cwd, project: project.isEmpty ? "Claude Code" : project)
        if let title = json["session_title"] as? String {
            let cleaned = ActivityPayload.sanitize(title, limit: 60)
            event.title = cleaned.isEmpty ? nil : cleaned
        }
        if kind == .permissionRequest {
            let tool = ActivityPayload.sanitize((json["tool_name"] as? String) ?? "Tool", limit: 80)
            event.toolName = tool
            event.detail = ToolRequestSummary.detail(toolName: tool, input: (json["tool_input"] as? [String: Any]) ?? [:], cwd: cwd, home: home)
            event.suggestion = alwaysAllow(from: json["permission_suggestions"])
        }
        return event
    }

    /// The first "allow" rule suggestion, if Claude Code sent one.
    private static func alwaysAllow(from value: Any?) -> AlwaysAllowSuggestion? {
        guard let suggestions = value as? [[String: Any]] else { return nil }
        for suggestion in suggestions {
            guard suggestion["type"] as? String == "addRules", suggestion["behavior"] as? String == "allow",
                  let rules = suggestion["rules"] as? [[String: Any]], let rule = rules.first,
                  let tool = rule["toolName"] as? String,
                  let data = try? JSONSerialization.data(withJSONObject: suggestion, options: [.sortedKeys]) else { continue }
            let content = rule["ruleContent"] as? String
            let label = SecretRedactor.redact(content.map { "\(tool)(\($0))" } ?? tool)
            return AlwaysAllowSuggestion(json: data, label: ToolRequestSummary.fit(label))
        }
        return nil
    }
}

/// What Notched tells Claude Code to do with a permission request. No reply
/// (nil) means "no decision": Claude Code shows its own prompt.
enum ClaudeHookReply: Equatable, Sendable {
    case allow
    case alwaysAllow(AlwaysAllowSuggestion)
    case deny(message: String, interrupt: Bool)

    /// The stdout `notched-hook` prints, in the PermissionRequest output format.
    var body: Data {
        var decision: [String: Any]
        switch self {
        case .allow:
            decision = ["behavior": "allow"]
        case .alwaysAllow(let suggestion):
            decision = ["behavior": "allow"]
            if let rule = try? JSONSerialization.jsonObject(with: suggestion.json) { decision["updatedPermissions"] = [rule] }
        case .deny(let message, let interrupt):
            decision = ["behavior": "deny", "message": message]
            if interrupt { decision["interrupt"] = true }
        }
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}
