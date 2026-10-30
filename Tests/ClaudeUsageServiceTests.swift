// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

private final class Logs: @unchecked Sendable {
    let root: URL
    private(set) var counter = 0

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("notched-usage-\(UUID().uuidString)/projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    static let now = Date(timeIntervalSince1970: 1_793_275_200) // 2026-10-29 12:00:00Z

    func stamp(minutesAgo: Double) -> String {
        Logs.now.addingTimeInterval(-minutesAgo * 60).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    func line(_ id: String, minutesAgo: Double = 1, model: String = "claude-opus-5-5", input: Int = 1000, output: Int = 100,
              session: String = "s1", cwd: String = "/x/Proj") -> String {
        #"{"type":"assistant","message":{"model":"\#(model)","id":"\#(id)","usage":{"input_tokens":\#(input),"output_tokens":\#(output)}},"requestId":"r\#(id)","timestamp":"\#(stamp(minutesAgo: minutesAgo))","sessionId":"\#(session)","cwd":"\#(cwd)"}"#
    }

    @discardableResult
    func write(_ lines: [String], to name: String = "-Users-c-Proj/s1.jsonl", terminated: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + (terminated ? "\n" : "")
        try Data(text.utf8).write(to: url)
        return url
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func service() -> ClaudeUsageService {
        let root = root
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return ClaudeUsageService(roots: { [root] }, calendar: calendar,
                                  pricing: ClaudePricing(updated: "t", models: [.init(match: "claude-opus-5*", input: 5, output: 25, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0)]))
    }
}

@Suite("ClaudeUsageService")
struct ClaudeUsageServiceTests {
    @Test("Reads every log under the projects folder, subagents included, and counts each response once")
    func reads() async throws {
        let logs = try Logs()
        try logs.write([logs.line("a"), logs.line("b"), logs.line("b")], to: "-Users-c-Proj/s1.jsonl")
        try logs.write([logs.line("c", session: "s1"), logs.line("a")], to: "-Users-c-Proj/s1/subagents/agent-x.jsonl")
        let snapshot = await logs.service().refresh(now: Logs.now)
        #expect(snapshot.today.tokens.input == 3000)
        #expect(snapshot.today.tokens.output == 300)
        #expect(snapshot.week.tokens.input == 3000)
        #expect(snapshot.models.map(\.model) == ["claude-opus-5-5"])
        let expected: Double = (3000.0 * 5.0 + 300.0 * 25.0) / 1_000_000.0
        #expect(abs(snapshot.today.cost - expected) < 1e-9)
        #expect(snapshot.pricingUpdated == "t")
    }

    @Test("A second refresh reads only what was appended")
    func incremental() async throws {
        let logs = try Logs()
        let url = try logs.write([logs.line("a")])
        let service = logs.service()
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 1000)
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 1000)
        try logs.append(logs.line("b") + "\n", to: url)
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 2000)
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 2000)
    }

    @Test("A half-written last line waits until it is finished")
    func partialLine() async throws {
        let logs = try Logs()
        let url = try logs.write([logs.line("a")])
        let service = logs.service()
        _ = await service.refresh(now: Logs.now)
        let second = logs.line("b")
        let cut = second.index(second.startIndex, offsetBy: second.count / 2)
        try logs.append(String(second[..<cut]), to: url)
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 1000)
        try logs.append(String(second[cut...]) + "\n", to: url)
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 2000)
    }

    @Test("A rewritten or truncated log is read again without double counting")
    func rotation() async throws {
        let logs = try Logs()
        let url = try logs.write([logs.line("a"), logs.line("b")])
        let service = logs.service()
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 2000)
        // Rewritten to the same size (the modification time moves).
        try logs.write([logs.line("a"), logs.line("c")])
        try FileManager.default.setAttributes([.modificationDate: Logs.now.addingTimeInterval(5)], ofItemAtPath: url.path)
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 3000)
        // Replaced by a longer file with a different start.
        try logs.write([logs.line("z", model: "claude-opus-5-5", session: "other"), logs.line("d"), logs.line("e")])
        try FileManager.default.setAttributes([.modificationDate: Logs.now.addingTimeInterval(10)], ofItemAtPath: url.path)
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 6000)
        // Truncated to nothing: what was counted stays, nothing is counted twice.
        try Data().write(to: url)
        #expect(await service.refresh(now: Logs.now).today.tokens.input == 6000)
    }

    @Test("Logs untouched for more than eight days are skipped, and so are old records")
    func old() async throws {
        let logs = try Logs()
        let stale = try logs.write([logs.line("old")], to: "-Users-c-Old/s9.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Logs.now.addingTimeInterval(-9 * 86_400)], ofItemAtPath: stale.path)
        try logs.write([logs.line("recent"), logs.line("ancient", minutesAgo: 60 * 24 * 10)])
        let snapshot = await logs.service().refresh(now: Logs.now)
        #expect(snapshot.week.tokens.input == 1000)
    }

    @Test("Sessions with a response in the last five minutes are active; the project name comes from the log")
    func activeSessions() async throws {
        let logs = try Logs()
        try logs.write([logs.line("a", minutesAgo: 2, session: "live", cwd: "/Users/c/Notched"), logs.line("b", minutesAgo: 30, session: "idle")])
        let snapshot = await logs.service().refresh(now: Logs.now)
        #expect(snapshot.activeSessions.map(\.id) == ["live"])
        #expect(snapshot.activeSessions.first?.project == "Notched")
    }

    @Test("Lines that look like usage but can't be read are counted, other lines are not")
    func unreadable() async throws {
        let logs = try Logs()
        try logs.write([logs.line("a"), #"{"type":"user","message":{"content":"hello"}}"#, #"{"type":"assistant","message":{"usage":{"output_tokens":5}}}"#,
                        #"garbage "output_tokens" in it"#, ""])
        let snapshot = await logs.service().refresh(now: Logs.now)
        #expect(snapshot.today.tokens.input == 1000)
        #expect(snapshot.skippedLines == 2)
    }

    @Test("A large log is streamed in chunks and read correctly, quickly")
    func large() async throws {
        let logs = try Logs()
        let lines = (0..<30_000).map { logs.line("m\($0)", minutesAgo: Double($0 % 600), input: 10, output: 1) }
        let url = try logs.write(lines)
        let size = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber).intValue
        #expect(size > 4 << 20) // bigger than three 1 MB chunks, so lines straddle chunk boundaries
        let start = Date()
        let snapshot = await logs.service().refresh(now: Logs.now)
        #expect(snapshot.week.tokens.input == 300_000)
        #expect(snapshot.week.tokens.output == 30_000)
        #expect(snapshot.skippedLines == 0)
        #expect(Date().timeIntervalSince(start) < 20)
    }

    @Test("No projects folder at all is an empty result, not an error")
    func none() async {
        let service = ClaudeUsageService(roots: { [] }, pricing: .empty)
        let snapshot = await service.refresh(now: Logs.now)
        #expect(snapshot.week.tokens.total == 0)
        #expect(snapshot.activeSessions.isEmpty)
    }

    @Test("Project names come from the folder Claude Code made")
    func projectNames() {
        let root = URL(fileURLWithPath: "/home/u/.claude/projects")
        #expect(ClaudeUsageService.projectName(from: root.appendingPathComponent("-Users-c-Notched/s.jsonl")) == "Notched")
        #expect(ClaudeUsageService.projectName(from: root.appendingPathComponent("-Users-c-Notched/s/subagents/agent-1.jsonl")) == "Notched")
    }
}
