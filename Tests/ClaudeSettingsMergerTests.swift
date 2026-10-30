// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

private let command = "/Users/c/.local/bin/notched-hook"

private func installed(_ text: String?) -> String {
    switch ClaudeSettingsMerger.install(into: text, command: command, approvalWait: 90) {
    case .success(let result): return result
    case .failure(let error): Issue.record("install failed: \(error)"); return ""
    }
}

private func parsed(_ text: String) -> OrderedJSON {
    if case .success(let value) = OrderedJSON.parse(text) { return value }
    Issue.record("didn't parse: \(text)")
    return .null
}

private func ourGroups(_ text: String, event: String) -> [OrderedJSON] {
    (parsed(text)["hooks"]?[event]?.elements ?? []).filter { group in
        (group["hooks"]?.elements ?? []).contains { ($0["command"]?.stringValue ?? "").hasSuffix("notched-hook") }
    }
}

@Suite("OrderedJSON")
struct OrderedJSONTests {
    @Test("Key order, numbers and unicode survive a round trip")
    func roundTrip() {
        let text = """
        {
          "z": 1,
          "a": [1, 2.50, -3e2, true, false, null],
          "m": {"é": "naïve \\u00e9 \\ud83d\\ude00", "b": ""},
          "q": "line\\nbreak \\"quoted\\" \\\\ tab\\t"
        }
        """
        let value = parsed(text)
        #expect(value.members?.map(\.key) == ["z", "a", "m", "q"])
        let again = parsed(value.pretty())
        #expect(again == value)
        #expect(value.pretty().contains("2.50"))
        #expect(value.pretty().contains("-3e2"))
        #expect(value["m"]?["é"]?.stringValue == "naïve é 😀")
        #expect(value.pretty().hasSuffix("}\n"))
    }

    @Test("Pretty output matches JSON.stringify(…, null, 2) style, with empties on one line")
    func pretty() {
        let value = parsed(#"{"a":{},"b":[],"c":[1,{"d":2}]}"#)
        #expect(value.pretty() == """
        {
          "a": {},
          "b": [],
          "c": [
            1,
            {
              "d": 2
            }
          ]
        }

        """)
    }

    @Test("Duplicate keys are kept in order")
    func duplicates() {
        #expect(parsed(#"{"a":1,"a":2}"#).members?.count == 2)
    }

    @Test("Invalid JSON is refused with a position")
    func invalid() {
        let bad = ["", "{", #"{"a":}"#, #"{"a":1,}"#, "[1,]", #"{"a" 1}"#, "{'a':1}", "01", "1.", "-", #"{"a":"\q"}"#, #""\ud800""#, "nul", "{\"a\":1} x", "\"unterminated", "[1 2]", "{\"a\":\"\u{01}\"}"]
        for text in bad {
            guard case .failure(let error) = OrderedJSON.parse(text) else { Issue.record("accepted \(text.debugDescription)"); continue }
            #expect(error.line >= 1 && error.column >= 1)
        }
        if case .failure(let error) = OrderedJSON.parse("{\n  \"a\": 1,\n  oops\n}") { #expect(error.line == 3) }
    }

    @Test("A byte-order mark is ignored; very deep nesting is refused, not a crash")
    func edgeCases() {
        #expect(OrderedJSON.parse("\u{FEFF}{}") == .success(.object([])))
        let deep = String(repeating: "[", count: 200) + String(repeating: "]", count: 200)
        guard case .failure = OrderedJSON.parse(deep) else { Issue.record("accepted deep nesting"); return }
    }
}

@Suite("ClaudeSettingsMerger")
struct ClaudeSettingsMergerTests {
    @Test("Installing into nothing creates a hooks object with every event")
    func fromScratch() {
        for input in [nil, "", "  \n", "{}"] as [String?] {
            let result = installed(input)
            for event in ClaudeSettingsMerger.events { #expect(ourGroups(result, event: event).count == 1, "\(event)") }
        }
    }

    @Test("Our entry runs the helper directly, with the event timeout rules")
    func entryShape() throws {
        let result = installed("{}")
        let group = try #require(ourGroups(result, event: "PermissionRequest").first)
        let handler = try #require(group["hooks"]?.elements?.first)
        #expect(handler["type"]?.stringValue == "command")
        #expect(handler["command"]?.stringValue == command)
        #expect(handler["args"]?.elements?.isEmpty == true)
        #expect(handler["timeout"] == .number("120"))
        let stop = try #require(ourGroups(result, event: "Stop").first?["hooks"]?.elements?.first)
        #expect(stop["timeout"] == .number("5"))
    }

    @Test("Other settings and other hooks are untouched, in their original order")
    func preserves() {
        let original = """
        {
          "model": "opus",
          "permissions": {"allow": ["Bash(ls)"]},
          "hooks": {
            "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "~/check.sh"}]}],
            "Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]
          },
          "env": {"A": "1"}
        }
        """
        let result = installed(original)
        let value = parsed(result)
        #expect(value.members?.map(\.key) == ["model", "permissions", "hooks", "env"])
        #expect(value["permissions"] == parsed(original)["permissions"])
        #expect(value["hooks"]?["PreToolUse"] == parsed(original)["hooks"]?["PreToolUse"])
        let stop = value["hooks"]?["Stop"]?.elements ?? []
        #expect(stop.count == 2)
        #expect(stop.first == parsed(original)["hooks"]?["Stop"]?.elements?.first)
        #expect(value["hooks"]?.members?.map(\.key).prefix(2) == ["PreToolUse", "Stop"])
    }

    @Test("Installing twice gives byte-identical output")
    func idempotent() {
        let once = installed(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]},"model":"x"}"#)
        #expect(installed(once) == once)
        #expect(installed(installed(once)) == once)
    }

    @Test("A changed path or timeout is replaced, not duplicated")
    func updates() {
        let old = installed("{}")
        let moved = ClaudeSettingsMerger.install(into: old, command: "/other/notched-hook", approvalWait: 60)
        guard case .success(let result) = moved else { Issue.record("failed"); return }
        for event in ClaudeSettingsMerger.events { #expect(ourGroups(result, event: event).count == 1) }
        #expect(result.contains("/other/notched-hook"))
        #expect(!result.contains(command))
        #expect(ClaudeSettingsMerger.status(of: old, command: "/other/notched-hook", approvalWait: 60) == .outdated)
        #expect(ClaudeSettingsMerger.status(of: old, command: command, approvalWait: 120) == .outdated)
    }

    @Test("A handler of ours inside a group that holds someone else's handler is replaced; theirs stays")
    func mixedGroup() {
        let original = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"},{"type":"command","command":"/old/notched-hook"}]}]}}"#
        let result = installed(original)
        let groups = parsed(result)["hooks"]?["Stop"]?.elements ?? []
        #expect(groups.count == 2)
        #expect(groups.first?["hooks"]?.elements?.count == 1)
        #expect(groups.first?["hooks"]?.elements?.first?["command"]?.stringValue == "say done")
    }

    @Test("Invalid JSON, a non-object file, and wrongly shaped hooks are refused")
    func refusals() {
        let cases: [(String, Bool)] = [
            ("{ not json", true), ("[1,2]", false), (#"{"hooks":[]}"#, false), (#"{"hooks":{"Stop":{}}}"#, false), (#"{"hooks":"x"}"#, false),
        ]
        for (text, isJSONError) in cases {
            switch ClaudeSettingsMerger.install(into: text, command: command, approvalWait: 90) {
            case .success: Issue.record("accepted \(text)")
            case .failure(let error):
                if isJSONError { guard case .invalidJSON = error else { Issue.record("wrong error for \(text)"); continue } }
                #expect(!error.message.isEmpty)
            }
            // Removal refuses the same files for the same reasons, except a list it has no reason to touch.
            if text != #"{"hooks":{"Stop":{}}}"# && text != "[1,2]" {
                guard case .failure = ClaudeSettingsMerger.remove(from: text) else { Issue.record("remove accepted \(text)"); continue }
            }
        }
    }

    @Test("Removing takes out only our entries, and what became empty because of us")
    func remove() {
        let original = #"{"model":"x","hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"a"}]}],"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        let withOurs = installed(original)
        guard case .success(let cleaned) = ClaudeSettingsMerger.remove(from: withOurs) else { Issue.record("remove failed"); return }
        #expect(parsed(cleaned) == parsed(original))
        for event in ClaudeSettingsMerger.events { #expect(ourGroups(cleaned, event: event).isEmpty) }
    }

    @Test("Removing from a file we created leaves no empty hooks object")
    func removeEmpties() {
        guard case .success(let cleaned) = ClaudeSettingsMerger.remove(from: installed("{}")) else { Issue.record("failed"); return }
        #expect(parsed(cleaned) == .object([]))
        guard case .success(let nothing) = ClaudeSettingsMerger.remove(from: #"{"a":1}"#) else { Issue.record("failed"); return }
        #expect(parsed(nothing) == parsed(#"{"a":1}"#))
    }

    @Test("Status: not installed, partly installed, installed")
    func status() {
        #expect(ClaudeSettingsMerger.status(of: nil, command: command, approvalWait: 90) == .notInstalled)
        #expect(ClaudeSettingsMerger.status(of: "{}", command: command, approvalWait: 90) == .notInstalled)
        #expect(ClaudeSettingsMerger.status(of: "garbage", command: command, approvalWait: 90) == .notInstalled)
        #expect(ClaudeSettingsMerger.status(of: installed("{}"), command: command, approvalWait: 90) == .installed)
        guard case .success(let partial) = ClaudeSettingsMerger.remove(from: #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/x/notched-hook"}]}]}}"#) else { return }
        #expect(ClaudeSettingsMerger.status(of: #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/x/notched-hook"}]}]}}"#, command: command, approvalWait: 90) == .partial)
        _ = partial
    }

    @Test("Someone else's hook that merely mentions the name isn't ours")
    func recognition() {
        let other = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo notched-hook-not"}]}]}}"#
        #expect(ClaudeSettingsMerger.status(of: other, command: command, approvalWait: 90) == .notInstalled)
        guard case .success(let cleaned) = ClaudeSettingsMerger.remove(from: other) else { Issue.record("failed"); return }
        #expect(parsed(cleaned) == parsed(other))
    }
}

@Suite("LineDiff")
struct LineDiffTests {
    @Test("Identical text has no diff")
    func same() {
        #expect(LineDiff.diff(old: "a\nb\n", new: "a\nb\n").isEmpty)
    }

    @Test("Added and removed lines are marked, with context and gaps")
    func changes() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 10", with: "line ten")
        let diff = LineDiff.diff(old: old, new: new, context: 1)
        #expect(diff.filter { $0.kind == .removed }.map(\.text) == ["line 10"])
        #expect(diff.filter { $0.kind == .added }.map(\.text) == ["line ten"])
        #expect(diff.filter { $0.kind == .gap }.count == 2)
        #expect(diff.filter { $0.kind == .same }.count == 2)
        #expect(Set(diff.map(\.id)).count == diff.count)
    }

    @Test("A new file is all additions")
    func newFile() {
        let diff = LineDiff.diff(old: "", new: "{\n}\n")
        #expect(diff.contains { $0.kind == .added && $0.text == "{" })
        #expect(!diff.contains { $0.kind == .removed && !$0.text.isEmpty })
    }
}
