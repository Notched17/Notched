// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

@Suite("SecretRedactor")
struct SecretRedactorTests {
    private func redacted(_ text: String) -> String { SecretRedactor.redact(text) }

    @Test("Known token formats are hidden")
    func tokens() {
        let secrets = [
            "sk-ant-api03-AbCdEfGhIjKlMnOpQrStUv", "sk-1234567890abcdefghijkl", "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
            "github_pat_11ABCDEFG0abcdefghijklmnop", "xoxb-1234567890-abcdef", "AKIAIOSFODNN7EXAMPLE",
            "AIzaSyA1234567890abcdefghijklmnopqrstuv", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r",
        ]
        for secret in secrets {
            let out = redacted("curl -H 'X-Key: \(secret)' https://api.example.com")
            #expect(!out.contains(secret), "\(secret) leaked: \(out)")
            #expect(out.contains(SecretRedactor.mask))
        }
    }

    @Test("Bearer, Authorization and flag values are hidden but the command stays readable")
    func headersAndFlags() {
        #expect(redacted("curl -H 'Authorization: Bearer abcdef123456' x") == "curl -H 'Authorization: ••••' x")
        #expect(redacted("curl -H \"authorization: Basic dXNlcjpwYXNz\" x") == "curl -H \"authorization: ••••\" x")
        #expect(redacted("mysql --password=hunter2 -u root") == "mysql --password=•••• -u root")
        #expect(redacted("tool --token abc123xyz run") == "tool --token •••• run")
        #expect(redacted("tool --api-key=zzz") == "tool --api-key=••••")
    }

    @Test("Environment assignments with secret-looking names are hidden")
    func environment() {
        #expect(redacted("GITHUB_TOKEN=abc123 npm publish") == "GITHUB_TOKEN=•••• npm publish")
        #expect(redacted("export DB_PASSWORD='p@ss word' && run") == "export DB_PASSWORD=•••• && run")
        #expect(redacted("API_KEY=\"x y\" ./go") == "API_KEY=•••• ./go")
        #expect(redacted("NODE_ENV=production npm test") == "NODE_ENV=production npm test")
    }

    @Test("URL credentials and private keys are hidden")
    func urlsAndKeys() {
        #expect(redacted("git clone https://user:s3cret@github.com/x/y.git") == "git clone https://user:••••@github.com/x/y.git")
        let key = "-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----"
        #expect(redacted("echo '\(key)' > k") == "echo '••••' > k")
        #expect(redacted("echo -----BEGIN PRIVATE KEY-----\nMIIE") == "echo ••••")
    }

    @Test("Long mixed letter-and-digit runs are hidden; plain words and paths are not")
    func longRuns() {
        #expect(redacted("run a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8") == "run ••••")
        #expect(redacted("cat /Users/charlie/Personal-Projects/Notched/Sources/Core/Island/IslandController.swift")
            == "cat /Users/charlie/Personal-Projects/Notched/Sources/Core/Island/IslandController.swift")
        #expect(redacted("thisisaverylongbutcompletelyordinaryidentifierwithnodigits") == "thisisaverylongbutcompletelyordinaryidentifierwithnodigits")
    }

    @Test("Ordinary commands pass through unchanged")
    func ordinary() {
        for command in ["npm test", "git status --short", "ls -la ~/Documents", "swift build -c release", "rm -rf node_modules"] {
            #expect(redacted(command) == command)
        }
    }
}

@Suite("ToolRequestSummary")
struct ToolRequestSummaryTests {
    private func detail(_ tool: String, _ input: [String: Any], cwd: String = "/Users/c/proj", home: String = "/Users/c") -> String {
        ToolRequestSummary.detail(toolName: tool, input: input, cwd: cwd, home: home)
    }

    @Test("Bash shows the command, redacted")
    func bash() {
        #expect(detail("Bash", ["command": "npm test"]) == "npm test")
        #expect(detail("Bash", ["command": "TOKEN=abc npm publish"]) == "TOKEN=•••• npm publish")
    }

    @Test("File tools show paths relative to the project or home")
    func paths() {
        #expect(detail("Edit", ["file_path": "/Users/c/proj/src/a.swift"]) == "src/a.swift")
        #expect(detail("Write", ["file_path": "/Users/c/.zshrc"]) == "~/.zshrc")
        #expect(detail("Read", ["file_path": "/etc/hosts"]) == "/etc/hosts")
        #expect(detail("Read", ["file_path": "/Users/c/proj"]) == ".")
        #expect(detail("Read", ["file_path": "/Users/c/project2/x"]) == "~/project2/x")
    }

    @Test("Web, search and MCP tools")
    func others() {
        #expect(detail("WebFetch", ["url": "https://example.com/a/b?token=zzz"]) == "example.com/a/b")
        #expect(detail("WebSearch", ["query": "swift concurrency"]) == "swift concurrency")
        #expect(detail("Grep", ["pattern": "TODO", "path": "/Users/c/proj/Sources"]) == "TODO in Sources")
        #expect(detail("mcp__github__create_issue", [:]) == "github › create_issue")
        #expect(detail("Mystery", ["x": "first"]) == "first")
        #expect(detail("Mystery", [:]) == "Mystery")
    }

    @Test("Long text is cut in the middle to 160 characters; newlines become spaces")
    func truncation() {
        let long = String(repeating: "a", count: 100) + "MIDDLE" + String(repeating: "z", count: 300)
        let out = detail("Bash", ["command": long])
        #expect(out.count == ToolRequestSummary.limit)
        #expect(out.contains("…"))
        #expect(out.hasPrefix("aaaa") && out.hasSuffix("zzzz"))
        #expect(detail("Bash", ["command": "echo a\necho b"]) == "echo a echo b")
        #expect(detail("Bash", ["command": "echo \u{202E}evil"]) == "echo evil")
    }
}

@Suite("ClaudeHookEvent")
struct ClaudeHookEventTests {
    private func parse(_ json: String) -> ClaudeHookEvent? { ClaudeHookEvent.parse(Data(json.utf8), home: "/Users/c") }

    @Test("A permission request carries the tool, a safe detail and the project")
    func permissionRequest() {
        let event = parse("""
        {"session_id":"abc","cwd":"/Users/c/Notched","permission_mode":"default","hook_event_name":"PermissionRequest",
         "tool_name":"Bash","tool_input":{"command":"rm -rf node_modules","description":"x"},
         "permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm -rf node_modules"}],"behavior":"allow","destination":"localSettings"}]}
        """)
        #expect(event?.kind == .permissionRequest)
        #expect(event?.sessionID == "abc")
        #expect(event?.project == "Notched")
        #expect(event?.toolName == "Bash")
        #expect(event?.detail == "rm -rf node_modules")
        #expect(event?.suggestion?.label == "Bash(rm -rf node_modules)")
    }

    @Test("The suggestion JSON is kept so it can be echoed back")
    func suggestionRoundTrip() throws {
        let event = parse(#"{"session_id":"a","cwd":"/x","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"},"permission_suggestions":[{"type":"setMode","mode":"acceptEdits"},{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"ls"}],"behavior":"allow","destination":"session"}]}"#)
        let suggestion = try #require(event?.suggestion)
        let object = try #require(JSONSerialization.jsonObject(with: suggestion.json) as? [String: Any])
        #expect(object["type"] as? String == "addRules")
        #expect(object["destination"] as? String == "session")
    }

    @Test("Only allow-rule suggestions count; secrets in the label are hidden")
    func suggestionFilter() {
        let deny = parse(#"{"session_id":"a","cwd":"/x","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"x"}],"behavior":"deny","destination":"session"}]}"#)
        #expect(deny?.suggestion == nil)
        let secret = parse(#"{"session_id":"a","cwd":"/x","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"TOKEN=abc123 run"}],"behavior":"allow","destination":"session"}]}"#)
        #expect(secret?.suggestion?.label == "Bash(TOKEN=•••• run)")
    }

    @Test("Other events are recognised")
    func kinds() {
        #expect(parse(#"{"session_id":"a","hook_event_name":"Stop"}"#)?.kind == .stop)
        #expect(parse(#"{"session_id":"a","hook_event_name":"SessionStart","source":"startup"}"#)?.kind == .sessionStart)
        #expect(parse(#"{"session_id":"a","hook_event_name":"UserPromptSubmit","prompt":"secret thoughts"}"#)?.kind == .userPromptSubmit)
        #expect(parse(#"{"session_id":"a","hook_event_name":"Notification","notification_type":"idle_prompt"}"#)?.kind == .notification(type: "idle_prompt"))
        #expect(parse(#"{"session_id":"a","hook_event_name":"StopFailure","error":"rate_limit"}"#)?.kind == .stopFailure(error: "rate_limit"))
        #expect(parse(#"{"session_id":"a","hook_event_name":"SessionEnd","reason":"clear"}"#)?.kind == .sessionEnd(reason: "clear"))
        #expect(parse(#"{"session_id":"a","hook_event_name":"PreCompact"}"#)?.kind == .other("PreCompact"))
    }

    @Test("The prompt text is never kept; the session title is")
    func privacy() {
        let event = parse(#"{"session_id":"a","hook_event_name":"UserPromptSubmit","prompt":"my password is hunter2","session_title":"Fix the bug"}"#)
        #expect(event?.title == "Fix the bug")
        #expect(event?.detail == nil)
        #expect(!"\(String(describing: event))".contains("hunter2"))
    }

    @Test("Bad payloads are refused")
    func bad() {
        for body in ["", "nope", "[]", "{}", #"{"session_id":"a"}"#, #"{"hook_event_name":"Stop"}"#, #"{"session_id":"","hook_event_name":"Stop"}"#] {
            #expect(parse(body) == nil, "\(body)")
        }
        #expect(ClaudeHookEvent.parse(Data(count: ClaudeHookEvent.maxBodyBytes + 1)) == nil)
    }

    @Test("Replies use Claude Code's PermissionRequest output format")
    func replies() throws {
        func object(_ reply: ClaudeHookReply) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: reply.body) as? [String: Any])
        }
        func decision(_ reply: ClaudeHookReply) throws -> [String: Any] {
            let output = try #require(try object(reply)["hookSpecificOutput"] as? [String: Any])
            #expect(output["hookEventName"] as? String == "PermissionRequest")
            return try #require(output["decision"] as? [String: Any])
        }
        #expect(try decision(.allow)["behavior"] as? String == "allow")
        let deny = try decision(.deny(message: "No", interrupt: false))
        #expect(deny["behavior"] as? String == "deny")
        #expect(deny["message"] as? String == "No")
        #expect(deny["interrupt"] == nil)
        #expect(try decision(.deny(message: "No", interrupt: true))["interrupt"] as? Bool == true)

        let suggestion = AlwaysAllowSuggestion(json: Data(#"{"type":"addRules","behavior":"allow","rules":[{"toolName":"Bash","ruleContent":"ls"}],"destination":"session"}"#.utf8), label: "Bash(ls)")
        let always = try decision(.alwaysAllow(suggestion))
        #expect(always["behavior"] as? String == "allow")
        let updated = try #require(always["updatedPermissions"] as? [[String: Any]])
        #expect(updated.first?["type"] as? String == "addRules")
    }
}
