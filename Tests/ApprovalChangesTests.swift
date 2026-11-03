// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// The changed lines on Claude's approval card: what an Edit shows, kept safe and short.
@Suite("Approval changes")
struct ApprovalChangesTests {
    private func kinds(_ lines: [LineDiff.Line]) -> [LineDiff.Line.Kind] { lines.map(\.kind) }

    @Test("An Edit shows its removed and added lines")
    func edit() {
        let lines = ToolRequestSummary.changes(toolName: "Edit", input: ["old_string": "const ttl = 3600", "new_string": "const ttl = 24 * 3600"])
        #expect(kinds(lines) == [.removed, .added])
        #expect(lines.map(\.text) == ["const ttl = 3600", "const ttl = 24 * 3600"])
    }

    @Test("Unchanged lines around a change give context, and a long stretch becomes a gap")
    func context() {
        let old = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 5", with: "line five")
        let lines = ToolRequestSummary.changes(toolName: "Edit", input: ["old_string": old, "new_string": new])
        #expect(lines.contains { $0.kind == .removed && $0.text == "line 5" })
        #expect(lines.contains { $0.kind == .added && $0.text == "line five" })
        #expect(lines.contains { $0.kind == .gap })
        #expect(lines.count <= ToolRequestSummary.maxChangeLines + 1)
    }

    @Test("A MultiEdit shows its first edit")
    func multiEdit() {
        let input: [String: Any] = ["edits": [["old_string": "a", "new_string": "b"], ["old_string": "x", "new_string": "y"]]]
        #expect(ToolRequestSummary.changes(toolName: "MultiEdit", input: input).map(\.text) == ["a", "b"])
    }

    @Test("Other tools, missing text and no-op edits show nothing")
    func nothing() {
        #expect(ToolRequestSummary.changes(toolName: "Bash", input: ["command": "ls"]).isEmpty)
        #expect(ToolRequestSummary.changes(toolName: "Write", input: ["content": "hello"]).isEmpty)
        #expect(ToolRequestSummary.changes(toolName: "Edit", input: ["old_string": "a"]).isEmpty)
        #expect(ToolRequestSummary.changes(toolName: "Edit", input: ["old_string": "same", "new_string": "same"]).isEmpty)
    }

    @Test("Secrets in an edit are masked before they reach the card")
    func redacted() {
        let key = "sk-ant-" + String(repeating: "a1B2", count: 8)
        let lines = ToolRequestSummary.changes(toolName: "Edit", input: ["old_string": "token = old", "new_string": "token = \(key)"])
        #expect(!lines.map(\.text).joined().contains(key))
    }

    @Test("Long lines are clipped, tabs and control characters cleaned")
    func clipped() {
        let long = String(repeating: "x", count: 200)
        let lines = ToolRequestSummary.changes(toolName: "Edit", input: ["old_string": "a\tb\u{07}c", "new_string": long])
        #expect(lines[0].text == "a  bc")
        #expect(lines[1].text.count == ToolRequestSummary.maxChangeLineLength)
        #expect(lines[1].text.hasSuffix("…"))
    }

    @Test("A big rewrite shows a few lines and then a gap")
    func capped() {
        let old = (1...20).map { "old \($0)" }.joined(separator: "\n")
        let new = (1...20).map { "new \($0)" }.joined(separator: "\n")
        let lines = ToolRequestSummary.changes(toolName: "Edit", input: ["old_string": old, "new_string": new])
        #expect(lines.count == ToolRequestSummary.maxChangeLines + 1)
        #expect(lines.last?.kind == .gap)
    }

    @Test("A permission request carries the changes, and the card model passes them on")
    @MainActor
    func hookToCard() throws {
        let body = """
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/Users/me/app","tool_name":"Edit",
         "tool_input":{"file_path":"/Users/me/app/src/a.ts","old_string":"one","new_string":"two"}}
        """
        let event = try #require(ClaudeHookEvent.parse(Data(body.utf8), home: "/Users/me"))
        #expect(event.detail == "src/a.ts")
        #expect(kinds(event.changes) == [.removed, .added])

        let approval = ClaudeSessionsReducer.Approval(id: "a1", toolName: "Edit", detail: "src/a.ts", suggestion: nil, changes: event.changes)
        let snapshot = ClaudeSessionsReducer.Snapshot(sessionID: "s1", project: "app", displayName: "app", title: nil, phase: .waitingForApproval,
                                                      since: nil, lastEvent: Date(), approval: approval, moreApprovals: 2)
        let model = ClaudePresentation.cardModel(snapshot, approval)
        #expect(model.brand == "Claude")
        #expect(model.badge == "+2")
        #expect(model.context == "app")
        #expect(model.changes == event.changes)
        #expect(model.detailStyle == .text)

        let bash = ClaudeSessionsReducer.Approval(id: "a2", toolName: "Bash", detail: "ls", suggestion: nil)
        #expect(ClaudePresentation.cardModel(snapshot, bash).detailStyle == .command)
    }
}
