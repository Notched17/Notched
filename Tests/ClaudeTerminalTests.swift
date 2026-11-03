// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// "Open Terminal" on the Claude waiting card: which app, and where the answer comes from.
@Suite("ClaudeTerminal")
struct ClaudeTerminalTests {
    @Test("The app the session reported is used when it is running")
    func reported() {
        let running: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2"]
        #expect(ClaudeTerminal.choose(reported: "com.googlecode.iterm2", running: running) == "com.googlecode.iterm2")
    }

    @Test("Without a report, the first known terminal that is running")
    func fallback() {
        #expect(ClaudeTerminal.choose(reported: nil, running: ["com.googlecode.iterm2", "com.mitchellh.ghostty"]) == "com.googlecode.iterm2")
        #expect(ClaudeTerminal.choose(reported: nil, running: ["com.apple.Terminal", "com.googlecode.iterm2"]) == "com.apple.Terminal")
    }

    @Test("A reported app that isn't running falls back; none running gives nil")
    func notRunning() {
        #expect(ClaudeTerminal.choose(reported: "com.mitchellh.ghostty", running: ["com.apple.Terminal"]) == "com.apple.Terminal")
        #expect(ClaudeTerminal.choose(reported: nil, running: ["com.apple.Safari"]) == nil)
    }

    @Test("A reported id that is not a plausible bundle id is ignored")
    func implausible() {
        #expect(!ClaudeTerminal.isPlausibleBundleID("rm -rf /"))
        #expect(!ClaudeTerminal.isPlausibleBundleID("nodots"))
        #expect(!ClaudeTerminal.isPlausibleBundleID(String(repeating: "a.", count: 100)))
        #expect(!ClaudeTerminal.isPlausibleBundleID("com.évil.app"))
        #expect(ClaudeTerminal.isPlausibleBundleID("com.apple.Terminal"))
        #expect(ClaudeTerminal.choose(reported: "../../etc", running: ["../../etc", "com.apple.Terminal"]) == "com.apple.Terminal")
    }

    @Test("The hook payload's terminal reaches the session's snapshot; junk does not")
    func throughTheHook() throws {
        func body(_ terminal: String?) -> Data {
            var json: [String: Any] = ["hook_event_name": "Notification", "notification_type": "idle_prompt", "session_id": "s1", "cwd": "/Users/me/app"]
            if let terminal { json["notched_terminal"] = terminal }
            return try! JSONSerialization.data(withJSONObject: json)
        }
        let event = try #require(ClaudeHookEvent.parse(body("com.googlecode.iterm2")))
        #expect(event.terminalApp == "com.googlecode.iterm2")
        #expect(try #require(ClaudeHookEvent.parse(body("not a bundle id"))).terminalApp == nil)
        #expect(try #require(ClaudeHookEvent.parse(body(nil))).terminalApp == nil)

        var reducer = ClaudeSessionsReducer()
        _ = reducer.reduce(.hook(event, approvalID: nil), now: Date())
        #expect(reducer.snapshot(of: "s1")?.terminalApp == "com.googlecode.iterm2")
        #expect(reducer.snapshot(of: "s1")?.phase == .waitingForInput)
    }
}
