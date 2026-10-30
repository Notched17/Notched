// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Adds and removes Notched's hooks in Claude Code's `settings.json` without
/// touching anything else in it (#63). Pure: text in, text out. Entries are
/// recognised by their command (`…/notched-hook`), so nobody else's hooks
/// are ever changed.
enum ClaudeSettingsMerger {
    /// The hook events Notched listens to.
    static let events = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
    static let executableName = "notched-hook"
    /// Seconds Claude Code lets a non-approval hook run.
    static let quickTimeout = 5

    enum MergeError: Error, Equatable, Sendable {
        case invalidJSON(String)
        case unexpectedStructure(String)

        var message: String {
            switch self {
            case .invalidJSON(let detail): "settings.json isn't valid JSON: \(detail). Fix or remove the problem and try again."
            case .unexpectedStructure(let detail): detail
            }
        }
    }

    enum Status: Equatable, Sendable {
        case notInstalled
        case installed
        /// Some events have it, some don't.
        case partial
        /// Installed, but with a different path or timeout than now.
        case outdated
    }

    /// The timeout for `PermissionRequest`: the island's wait plus slack, so
    /// `notched-hook` always exits before Claude Code would cancel it.
    static func approvalTimeout(wait: Int) -> Int { wait + 30 }

    static func group(for event: String, command: String, approvalWait: Int) -> OrderedJSON {
        let timeout = event == "PermissionRequest" ? approvalTimeout(wait: approvalWait) : quickTimeout
        return .object([.init(key: "hooks", value: .array([
            .object([
                .init(key: "type", value: .string("command")),
                .init(key: "command", value: .string(command)),
                .init(key: "args", value: .array([])),
                .init(key: "timeout", value: .number(String(timeout))),
            ]),
        ]))])
    }

    // MARK: Install

    static func install(into text: String?, command: String, approvalWait: Int) -> Result<String, MergeError> {
        switch parseRoot(text) {
        case .failure(let error): return .failure(error)
        case .success(let root):
            var members = root.members ?? []
            let hooksIndex = members.firstIndex { $0.key == "hooks" }
            var hooks: [OrderedJSON.Member]
            if let index = hooksIndex {
                guard let existing = members[index].value.members else {
                    return .failure(.unexpectedStructure("\"hooks\" in settings.json isn't an object, so Notched left the file alone."))
                }
                hooks = existing
            } else {
                hooks = []
            }

            for event in events {
                let wanted = group(for: event, command: command, approvalWait: approvalWait)
                guard let position = hooks.firstIndex(where: { $0.key == event }) else {
                    hooks.append(.init(key: event, value: .array([wanted])))
                    continue
                }
                guard var groups = hooks[position].value.elements else {
                    return .failure(.unexpectedStructure("\"hooks.\(event)\" in settings.json isn't a list, so Notched left the file alone."))
                }
                // Already exactly right: leave the order alone (installing twice changes nothing).
                if groups.contains(wanted), !groups.contains(where: { isOurs($0) && $0 != wanted }) { continue }
                groups = removeOurs(from: groups)
                groups.append(wanted)
                hooks[position].value = .array(groups)
            }

            if let index = hooksIndex {
                members[index].value = .object(hooks)
            } else {
                members.append(.init(key: "hooks", value: .object(hooks)))
            }
            return .success(OrderedJSON.object(members).pretty())
        }
    }

    // MARK: Remove

    /// Takes out only Notched's entries, and any group or list that became
    /// empty because of that.
    static func remove(from text: String) -> Result<String, MergeError> {
        switch parseRoot(text) {
        case .failure(let error): return .failure(error)
        case .success(let root):
            var members = root.members ?? []
            guard let hooksIndex = members.firstIndex(where: { $0.key == "hooks" }) else { return .success(root.pretty()) }
            guard var hooks = members[hooksIndex].value.members else {
                return .failure(.unexpectedStructure("\"hooks\" in settings.json isn't an object, so Notched left the file alone."))
            }
            hooks = hooks.compactMap { (member: OrderedJSON.Member) -> OrderedJSON.Member? in
                guard let groups = member.value.elements else { return member }
                let kept = removeOurs(from: groups)
                if kept == groups { return member }
                return kept.isEmpty ? nil : .init(key: member.key, value: .array(kept))
            }
            if hooks.isEmpty {
                members.remove(at: hooksIndex)
            } else {
                members[hooksIndex].value = .object(hooks)
            }
            return .success(OrderedJSON.object(members).pretty())
        }
    }

    // MARK: Status

    static func status(of text: String?, command: String, approvalWait: Int) -> Status {
        guard case .success(let root) = parseRoot(text), let hooks = root["hooks"]?.members else { return .notInstalled }
        var present = 0
        var current = 0
        for event in events {
            guard let groups = hooks.first(where: { $0.key == event })?.value.elements else { continue }
            let ours = groups.filter(isOurs)
            guard !ours.isEmpty else { continue }
            present += 1
            if ours == [group(for: event, command: command, approvalWait: approvalWait)] { current += 1 }
        }
        if present == 0 { return .notInstalled }
        if present < events.count { return .partial }
        return current == events.count ? .installed : .outdated
    }

    // MARK: Helpers

    private static func parseRoot(_ text: String?) -> Result<OrderedJSON, MergeError> {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .success(.object([])) }
        switch OrderedJSON.parse(text) {
        case .failure(let error): return .failure(.invalidJSON(error.description))
        case .success(let value):
            guard value.members != nil else { return .failure(.unexpectedStructure("settings.json isn't a JSON object, so Notched left the file alone.")) }
            return .success(value)
        }
    }

    private static func isOurHandler(_ handler: OrderedJSON) -> Bool {
        guard let command = handler["command"]?.stringValue else { return false }
        return command == executableName || command.hasSuffix("/" + executableName)
    }

    private static func isOurs(_ group: OrderedJSON) -> Bool {
        group["hooks"]?.elements?.contains(where: isOurHandler) ?? false
    }

    /// The groups with Notched's handlers removed; a group left with no
    /// handlers goes too.
    private static func removeOurs(from groups: [OrderedJSON]) -> [OrderedJSON] {
        groups.compactMap { (group: OrderedJSON) -> OrderedJSON? in
            guard var members = group.members, let index = members.firstIndex(where: { $0.key == "hooks" }),
                  let handlers = members[index].value.elements, handlers.contains(where: isOurHandler) else { return group }
            let kept = handlers.filter { !isOurHandler($0) }
            guard !kept.isEmpty else { return nil }
            members[index].value = .array(kept)
            return .object(members)
        }
    }
}
