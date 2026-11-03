// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// "Show what Claude is working on": the line, the opt-in hook, and how the card follows it.
@Suite("Claude activity")
struct ClaudeActivityTests {
    private func line(_ tool: String, _ input: [String: Any]) -> ClaudeActivityLine { ClaudeActivity.line(toolName: tool, input: input) }

    @Test("Files show their name, never their folders")
    func files() {
        #expect(line("Edit", ["file_path": "/Users/me/app/src/auth/session.ts"]).text == "Editing session.ts")
        #expect(line("MultiEdit", ["file_path": "/a/b/c.swift"]).text == "Editing c.swift")
        #expect(line("Write", ["file_path": "/a/NEW.md"]).text == "Writing NEW.md")
        #expect(line("Read", ["file_path": "/etc/hosts"]).text == "Reading hosts")
        #expect(line("Read", ["file_path": "/Users/me/secret-folder/notes.txt"]).target == "notes.txt")
    }

    @Test("A command shows its first words only")
    func commands() {
        #expect(line("Bash", ["command": "npm run test -- --coverage --watch"]).text == "Running npm run test")
        #expect(line("Bash", ["command": "ls\nrm -rf /"]).text == "Running ls")
        #expect(line("Bash", [:]).text == "Running")
        #expect(line("Bash", ["command": "   "]).text == "Running")
    }

    @Test("Secrets in a command or pattern are masked")
    func secrets() {
        let key = "sk-ant-" + String(repeating: "a1B2", count: 8)
        #expect(!line("Bash", ["command": "curl -H \(key) x"]).text.contains(key))
        #expect(!line("Grep", ["pattern": key]).text.contains(key))
    }

    @Test("Searches, fetches and the rest")
    func others() {
        #expect(line("Grep", ["pattern": "ttl"]).text == "Searching \u{201C}ttl\u{201D}")
        #expect(line("Glob", ["pattern": "**/*.ts"]).text == "Finding **/*.ts")
        #expect(line("WebFetch", ["url": "https://example.com/a/b?q=1"]).text == "Fetching example.com")
        #expect(line("WebSearch", ["query": "private query"]).text == "Searching the web")
        #expect(line("Task", ["description": "private"]).text == "Running a subagent")
        #expect(line("TodoWrite", [:]).text == "Planning")
        #expect(line("mcp__github__create_issue", [:]).text == "Using github › create_issue")
        #expect(line("Frobnicate", [:]).text == "Using Frobnicate")
    }

    @Test("Hidden characters never reach the line, and a long target is clipped")
    func cleaned() {
        #expect(line("Read", ["file_path": "/a/we\u{202E}ird\u{200B}.txt"]).target == "weird.txt")
        let long = line("Read", ["file_path": "/a/" + String(repeating: "x", count: 200)])
        #expect(long.target?.count == ClaudeActivity.targetLimit)
        #expect(long.target?.hasSuffix("…") == true)
    }

    // MARK: The hook

    private let command = "/Users/me/.local/bin/notched-hook"

    @Test("Installing with the setting on adds PreToolUse; off leaves it out")
    func installsOnlyWhenOn() throws {
        let off = try ClaudeSettingsMerger.install(into: nil, command: command, approvalWait: 90).get()
        #expect(!off.contains("PreToolUse"))
        let on = try ClaudeSettingsMerger.install(into: nil, command: command, approvalWait: 90, activity: true).get()
        #expect(on.contains("PreToolUse"))
        #expect(ClaudeSettingsMerger.status(of: on, command: command, approvalWait: 90, activity: true) == .installed)
    }

    @Test("Switching the setting off and updating takes our PreToolUse out, and only ours")
    func switchingOff() throws {
        let mine = try ClaudeSettingsMerger.install(into: nil, command: command, approvalWait: 90, activity: true).get()
        // Someone else's PreToolUse hook sits beside ours.
        let shared = mine.replacingOccurrences(of: "\"PreToolUse\": [", with: "\"PreToolUse\": [{\"hooks\":[{\"type\":\"command\",\"command\":\"/usr/bin/other\"}]},")
        #expect(shared != mine)
        #expect(ClaudeSettingsMerger.status(of: shared, command: command, approvalWait: 90, activity: false) == .outdated)
        let updated = try ClaudeSettingsMerger.install(into: shared, command: command, approvalWait: 90, activity: false).get()
        #expect(updated.contains("/usr/bin/other"))
        #expect(updated.contains("PreToolUse"))
        #expect(ClaudeSettingsMerger.status(of: updated, command: command, approvalWait: 90, activity: false) == .installed)
        // With nothing else there, the empty list goes too.
        let alone = try ClaudeSettingsMerger.install(into: mine, command: command, approvalWait: 90, activity: false).get()
        #expect(!alone.contains("PreToolUse"))
    }

    @Test("Without the setting on, a plain install is still just installed")
    func plainStatus() throws {
        let plain = try ClaudeSettingsMerger.install(into: nil, command: command, approvalWait: 90).get()
        #expect(ClaudeSettingsMerger.status(of: plain, command: command, approvalWait: 90) == .installed)
        // The setting on, but the hook not installed yet: partly there.
        #expect(ClaudeSettingsMerger.status(of: plain, command: command, approvalWait: 90, activity: true) == .partial)
    }

    @Test("Removing the hooks takes PreToolUse out too")
    func removal() throws {
        let mine = try ClaudeSettingsMerger.install(into: nil, command: command, approvalWait: 90, activity: true).get()
        let removed = try ClaudeSettingsMerger.remove(from: mine).get()
        #expect(!removed.contains("PreToolUse") && !removed.contains("notched-hook"))
    }

    // MARK: The card

    private func hook(_ name: String, tool: String? = nil, input: [String: Any] = [:], extra: [String: Any] = [:]) throws -> ClaudeHookEvent {
        var json: [String: Any] = ["hook_event_name": name, "session_id": "s1", "cwd": "/Users/me/app"]
        if let tool { json["tool_name"] = tool; json["tool_input"] = input }
        json.merge(extra) { $1 }
        return try #require(ClaudeHookEvent.parse(try JSONSerialization.data(withJSONObject: json)))
    }

    @Test("A tool call puts the session to work and names what it is doing; a repeat changes nothing")
    func reducer() throws {
        var reducer = ClaudeSessionsReducer()
        let t = Date(timeIntervalSinceReferenceDate: 1_000)
        let edit = try hook("PreToolUse", tool: "Edit", input: ["file_path": "/a/session.ts"])
        let first = reducer.reduce(.hook(edit, approvalID: nil), now: t)
        #expect(first.contains { if case .post = $0 { true } else { false } })
        #expect(reducer.snapshot(of: "s1")?.phase == .working)
        #expect(reducer.snapshot(of: "s1")?.activity?.text == "Editing session.ts")

        let repeated = reducer.reduce(.hook(edit, approvalID: nil), now: t + 1)
        #expect(!repeated.contains { if case .post = $0 { true } else { false } })

        let bash = try hook("PreToolUse", tool: "Bash", input: ["command": "npm test"])
        let changed = reducer.reduce(.hook(bash, approvalID: nil), now: t + 2)
        #expect(changed.contains { if case .post = $0 { true } else { false } })
        #expect(reducer.snapshot(of: "s1")?.activity?.verb == "Running")
    }

    @Test("The activity ends with the work: a prompt, an idle wait or a stop clear it")
    func clears() throws {
        var reducer = ClaudeSessionsReducer()
        let t = Date(timeIntervalSinceReferenceDate: 1_000)
        let edit = try hook("PreToolUse", tool: "Edit", input: ["file_path": "/a/x.ts"])
        _ = reducer.reduce(.hook(edit, approvalID: nil), now: t)
        _ = reducer.reduce(.hook(try hook("Notification", extra: ["notification_type": "idle_prompt"]), approvalID: nil), now: t + 5)
        #expect(reducer.snapshot(of: "s1")?.phase == .waitingForInput)
        #expect(reducer.snapshot(of: "s1")?.activity == nil)

        _ = reducer.reduce(.hook(edit, approvalID: nil), now: t + 10)
        _ = reducer.reduce(.hook(try hook("Stop"), approvalID: nil), now: t + 20)
        #expect(reducer.snapshot(of: "s1")?.activity == nil)
    }

    @Test("While a permission card is up, tool calls don't take over the island")
    func approvalWins() throws {
        var reducer = ClaudeSessionsReducer()
        let t = Date(timeIntervalSinceReferenceDate: 1_000)
        _ = reducer.reduce(.hook(try hook("PermissionRequest", tool: "Bash", input: ["command": "ls"]), approvalID: "a1"), now: t)
        let other = try hook("PreToolUse", tool: "Read", input: ["file_path": "/a/b.txt"])
        let effects = reducer.reduce(.hook(other, approvalID: nil), now: t + 1)
        #expect(!effects.contains { if case .post = $0 { true } else { false } })
        #expect(reducer.snapshot(of: "s1")?.phase == .waitingForApproval)
    }

    @Test("The setting is off by default and remembered")
    @MainActor
    func setting() throws {
        let suite = "ClaudeActivityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ClaudeCodeSettings(defaults: defaults)
        #expect(!settings.showActivity)
        settings.showActivity = true
        #expect(ClaudeCodeSettings(defaults: defaults).showActivity)
    }
}
