// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// Lines shaped like Claude Code 2.1.x session logs (ids and content removed).
private enum Fixture {
    static let assistant = #"{"parentUuid":"00000000-0000-0000-0000-000000000001","isSidechain":false,"type":"assistant","message":{"model":"claude-opus-5-5","id":"msg_01TESTAAAA","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{}}],"stop_reason":"tool_use","usage":{"input_tokens":2,"cache_creation_input_tokens":10922,"cache_read_input_tokens":140554,"output_tokens":437,"cache_creation":{"ephemeral_1h_input_tokens":10922,"ephemeral_5m_input_tokens":0},"service_tier":"standard","speed":"standard"}},"requestId":"req_01TESTAAAA","type":"assistant","uuid":"00000000-0000-0000-0000-000000000002","timestamp":"2026-10-29T23:19:28.457Z","cwd":"/home/user/Notched","sessionId":"11111111-1111-1111-1111-111111111111","version":"2.1.312"}"#

    static func line(id: String = "msg_1", request: String? = "req_1", model: String = "claude-opus-5-5", timestamp: String = "2026-10-29T10:00:00.000Z",
                     input: Int = 100, output: Int = 50, write: Int = 0, read: Int = 0, session: String = "s1") -> String {
        let requestPart = request.map { #","requestId":"\#($0)""# } ?? ""
        return #"{"type":"assistant","message":{"model":"\#(model)","id":"\#(id)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(write),"cache_read_input_tokens":\#(read)}}\#(requestPart),"timestamp":"\#(timestamp)","sessionId":"\#(session)","cwd":"/x/Proj"}"#
    }

    static func record(_ text: String) -> UsageRecord? { ClaudeUsageParser.parse(line: Data(text.utf8)) }
}

@Suite("ClaudeUsageParser")
struct ClaudeUsageParserTests {
    @Test("A real-shaped assistant line is read in full")
    func realLine() {
        let record = Fixture.record(Fixture.assistant)
        #expect(record?.messageID == "msg_01TESTAAAA")
        #expect(record?.requestID == "req_01TESTAAAA")
        #expect(record?.model == "claude-opus-5-5")
        #expect(record?.input == 2)
        #expect(record?.output == 437)
        #expect(record?.cacheRead == 140_554)
        #expect(record?.cacheWrite1h == 10_922)
        #expect(record?.cacheWrite5m == 0)
        #expect(record?.sessionID == "11111111-1111-1111-1111-111111111111")
        #expect(record?.cwd == "/home/user/Notched")
        #expect(record?.timestamp == Date(timeIntervalSince1970: 1_793_315_968.457))
    }

    @Test("Lines without usage, of other types, or unreadable are skipped")
    func skipped() {
        let skip = [
            #"{"type":"user","message":{"role":"user","content":"hi"},"timestamp":"2026-10-29T10:00:00Z"}"#,
            #"{"type":"ai-title","aiTitle":"x","sessionId":"s"}"#,
            #"{"type":"assistant","message":{"id":"m","model":"x"},"timestamp":"2026-10-29T10:00:00Z"}"#,
            #"{"type":"user","message":{"usage":{"output_tokens":5},"id":"m"},"timestamp":"2026-10-29T10:00:00Z"}"#,
            "", "not json at all", #"{"output_tokens": "#, "[1,2,3]", #"["output_tokens"]"#,
            #"{"type":"assistant","message":{"id":"m","model":"x","usage":{"output_tokens":5}},"timestamp":"yesterday"}"#,
            #"{"type":"assistant","message":{"id":"m","model":"x","usage":{"output_tokens":5}}}"#,
            #"{"type":"assistant","message":{"model":"x","usage":{"output_tokens":5}},"timestamp":"2026-10-29T10:00:00Z"}"#,
        ]
        for text in skip { #expect(Fixture.record(text) == nil, "\(text)") }
    }

    @Test("Decoding tells 'not usage' apart from 'looks like usage but unreadable'")
    func outcomes() {
        func outcome(_ text: String) -> ClaudeUsageParser.Outcome { ClaudeUsageParser.decode(line: Data(text.utf8)) }
        #expect(outcome(#"{"type":"user","message":{"content":"hi"}}"#) == .ignored)
        #expect(outcome(#"{"type":"user","message":{"usage":{"output_tokens":5}}}"#) == .ignored)
        #expect(outcome(Fixture.line(model: "<synthetic>")) == .ignored)
        #expect(outcome(#"{"output_tokens": "#) == .unreadable)
        #expect(outcome(#"{"type":"assistant","message":{"id":"m","usage":{"output_tokens":5}}}"#) == .unreadable)
        #expect(outcome(#"{"type":"assistant","message":{"usage":{"output_tokens":5}},"timestamp":"2026-10-29T10:00:00Z"}"#) == .unreadable)
        if case .record = outcome(Fixture.assistant) {} else { Issue.record("expected a record") }
    }

    @Test("Claude Code's synthetic placeholder messages cost nothing")
    func synthetic() {
        #expect(Fixture.record(Fixture.line(model: "<synthetic>")) == nil)
    }

    @Test("Format drift: missing split, strings, negatives, floats, extra fields, no model")
    func drift() {
        // No cache_creation split: all cache writes count as 5-minute writes.
        #expect(Fixture.record(Fixture.line(write: 500))?.cacheWrite5m == 500)
        #expect(Fixture.record(Fixture.line(write: 500))?.cacheWrite1h == 0)
        // A split that doesn't add up: the rest is a 5-minute write.
        let partial = #"{"type":"assistant","message":{"id":"m","model":"x","usage":{"output_tokens":1,"cache_creation_input_tokens":100,"cache_creation":{"ephemeral_1h_input_tokens":30}}},"timestamp":"2026-10-29T10:00:00Z"}"#
        #expect(Fixture.record(partial)?.cacheWrite1h == 30)
        #expect(Fixture.record(partial)?.cacheWrite5m == 70)
        // Strings, negatives and booleans count as zero; floats are truncated; huge values are capped.
        let odd = #"{"type":"assistant","message":{"id":"m","model":"x","usage":{"input_tokens":"12","output_tokens":-5,"cache_read_input_tokens":true,"cache_creation_input_tokens":7.9}},"timestamp":"2026-10-29T10:00:00Z"}"#
        let record = Fixture.record(odd)
        #expect(record?.input == 0)
        #expect(record?.output == 0)
        #expect(record?.cacheRead == 0)
        #expect(record?.cacheWrite5m == 7)
        let huge = #"{"type":"assistant","message":{"id":"m","model":"x","usage":{"output_tokens":1e300}},"timestamp":"2026-10-29T10:00:00Z"}"#
        #expect(Fixture.record(huge)?.output == 1_000_000_000_000)
        // No model: kept, as "unknown".
        let noModel = #"{"type":"assistant","message":{"id":"m","usage":{"output_tokens":5}},"timestamp":"2026-10-29T10:00:00Z"}"#
        #expect(Fixture.record(noModel)?.model == "unknown")
        #expect(Fixture.record(noModel)?.requestID == nil)
    }

    @Test("A byte-order mark, a trailing CR, and timestamps without fractions are fine")
    func quirks() {
        let plain = Fixture.line(timestamp: "2026-10-29T10:00:00Z")
        #expect(Fixture.record(plain)?.timestamp == Date(timeIntervalSince1970: 1_793_268_000))
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(Data(plain.utf8))
        #expect(ClaudeUsageParser.parse(line: bom) != nil)
        #expect(ClaudeUsageParser.parse(line: Data((plain + "\r").utf8)) != nil)
    }

    @Test("Fuzz: truncated and mutated real lines never crash")
    func fuzz() {
        var seed: UInt64 = 99
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        let bytes = Array(Fixture.assistant.utf8)
        for cut in stride(from: 0, to: bytes.count, by: 7) { _ = ClaudeUsageParser.parse(line: Data(bytes.prefix(cut))) }
        for _ in 0..<2000 {
            var mutated = bytes
            for _ in 0..<(next(4) + 1) { mutated[next(mutated.count)] = UInt8(truncatingIfNeeded: next(256)) }
            _ = ClaudeUsageParser.parse(line: Data(mutated))
        }
    }
}

@Suite("ClaudePricing")
struct ClaudePricingTests {
    private let table = ClaudePricing(updated: "test", models: [
        .init(match: "claude-opus-5*", input: 5, output: 25, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5),
        .init(match: "claude-opus-5-5*", input: 4, output: 20, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.2),
        .init(match: "exact-model", input: 1, output: 2, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0),
    ])

    @Test("The longest matching pattern wins; patterns without * must match exactly")
    func matching() {
        #expect(table.price(for: "claude-opus-5-5")?.input == 4)
        #expect(table.price(for: "claude-opus-5-5-20261001")?.input == 4)
        #expect(table.price(for: "claude-opus-5")?.input == 5)
        #expect(table.price(for: "CLAUDE-OPUS-5-1")?.input == 5)
        #expect(table.price(for: "exact-model")?.input == 1)
        #expect(table.price(for: "exact-model-2") == nil)
        #expect(table.price(for: "gpt-5") == nil)
    }

    @Test("Cost is per million tokens across all five kinds")
    func cost() {
        let tokens = TokenCounts(input: 1_000_000, output: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000, cacheRead: 1_000_000)
        let expected: Double = 4.0 + 20.0 + 5.0 + 8.0 + 0.2
        #expect(table.cost(of: tokens, model: "claude-opus-5-5") == expected)
        #expect(table.cost(of: TokenCounts(input: 500_000), model: "claude-opus-5") == 2.5)
        #expect(table.cost(of: tokens, model: "unknown") == nil)
    }

    @Test("The bundled price file decodes, and a bad file is rejected")
    func decoding() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Modules/ClaudeCode/claude-pricing.json")
        let data = try Data(contentsOf: url)
        let pricing = try #require(ClaudePricing.decode(data))
        #expect(pricing.models.count > 10)
        #expect(pricing.price(for: "claude-opus-5-5")?.input == 4)
        #expect(pricing.price(for: "claude-sonnet-5-5")?.output == 10)
        #expect(pricing.price(for: "claude-haiku-4-5-20251001")?.input == 1)
        #expect(pricing.price(for: "claude-fable-5-1")?.output == 50)
        #expect(ClaudePricing.decode(Data("{}".utf8)) == nil)
        #expect(ClaudePricing.decode(Data(#"{"version":2,"models":[]}"#.utf8)) == nil)
        #expect(ClaudePricing.decode(Data("nope".utf8)) == nil)
    }
}

@Suite("ClaudeUsageAggregator")
struct ClaudeUsageAggregatorTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private let pricing = ClaudePricing(updated: nil, models: [
        .init(match: "priced*", input: 1, output: 2, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0),
    ])

    private func record(_ id: String, _ stamp: String, model: String = "priced", input: Int = 1_000_000, output: Int = 0) -> UsageRecord {
        ClaudeUsageParser.parse(line: Data(Fixture.line(id: id, request: nil, model: model, timestamp: stamp, input: input, output: output).utf8))!
    }

    @Test("The same response on several lines is counted once")
    func dedupe() {
        var sut = ClaudeUsageAggregator(calendar: calendar("UTC"))
        let one = record("m1", "2026-10-29T10:00:00Z")
        let first = sut.add(one)
        let again = sut.add(one)
        let sameMessageLater = sut.add(record("m1", "2026-10-29T10:00:01Z"))
        let other = sut.add(record("m2", "2026-10-29T10:00:02Z"))
        #expect(first && other)
        #expect(!again && !sameMessageLater)
        let now = Date(timeIntervalSince1970: 1_793_268_000 + 3600)
        #expect(sut.today(now: now, pricing: pricing).tokens.input == 2_000_000)
    }

    @Test("Days are local days: the same instant lands on different days in different zones")
    func timeZones() {
        let instant = "2026-10-29T20:00:00Z"
        var utc = ClaudeUsageAggregator(calendar: calendar("UTC"))
        var brisbane = ClaudeUsageAggregator(calendar: calendar("Australia/Brisbane"))
        _ = utc.add(record("m1", instant))
        _ = brisbane.add(record("m1", instant))
        let utcMorning = Date(timeIntervalSince1970: 1_793_318_400 - 4 * 3600) // 2026-10-29 20:00Z, still "today" in UTC
        let brisbaneNextMorning = Date(timeIntervalSince1970: 1_793_318_400 + 3600) // 2026-10-30 01:00 Brisbane = 2026-10-29 21:00Z... 
        #expect(utc.today(now: utcMorning, pricing: pricing).tokens.input == 1_000_000)
        // 20:00Z is 06:00 on the 30th in Brisbane, so it isn't "today" on the 29th there.
        #expect(brisbane.today(now: Date(timeIntervalSince1970: 1_793_268_000), pricing: pricing).tokens.input == 0)
        #expect(brisbane.today(now: brisbaneNextMorning, pricing: pricing).tokens.input == 1_000_000)
    }

    @Test("Today, this week (last 7 days including today) and daily bars")
    func windows() {
        var sut = ClaudeUsageAggregator(calendar: calendar("UTC"))
        // now = 2026-10-29 12:00Z
        let now = Date(timeIntervalSince1970: 1_793_275_200)
        _ = sut.add(record("today", "2026-10-29T01:00:00Z"))
        _ = sut.add(record("d6", "2026-10-23T23:59:00Z"))   // 6 days ago: inside
        _ = sut.add(record("d7", "2026-10-22T23:59:00Z"))   // 7 days ago: outside the week
        #expect(sut.today(now: now, pricing: pricing).tokens.input == 1_000_000)
        #expect(sut.week(now: now, pricing: pricing).tokens.input == 2_000_000)
        let days = sut.daily(now: now, pricing: pricing)
        #expect(days.count == 7)
        #expect(days.last?.totals.tokens.input == 1_000_000)
        #expect(days.first?.totals.tokens.input == 1_000_000)
        #expect(days[1...5].allSatisfy { $0.totals.tokens.total == 0 })
        #expect(days.map(\.day) == days.map(\.day).sorted())
    }

    @Test("Cost uses the model's price; unpriced models are counted as tokens, not as $0")
    func costs() {
        var sut = ClaudeUsageAggregator(calendar: calendar("UTC"))
        let now = Date(timeIntervalSince1970: 1_793_275_200)
        _ = sut.add(record("a", "2026-10-29T01:00:00Z", model: "priced-1", input: 1_000_000, output: 500_000))
        _ = sut.add(record("b", "2026-10-29T02:00:00Z", model: "mystery", input: 3_000_000))
        let totals = sut.today(now: now, pricing: pricing)
        #expect(totals.cost == 2.0)
        #expect(totals.unpricedTokens == 3_000_000)
        #expect(totals.tokens.total == 4_500_000)
        let models = sut.models(now: now, pricing: pricing)
        #expect(models.map(\.model) == ["mystery", "priced-1"])
        #expect(models.first?.totals.unpricedTokens == 3_000_000)
        #expect(models.last?.totals.cost == 2.0)
    }

    @Test("Old days are pruned")
    func prune() {
        var sut = ClaudeUsageAggregator(calendar: calendar("UTC"))
        _ = sut.add(record("old", "2026-10-01T01:00:00Z"))
        _ = sut.add(record("new", "2026-10-29T01:00:00Z"))
        sut.prune(now: Date(timeIntervalSince1970: 1_793_275_200))
        let isEmpty = sut.isEmpty
        #expect(!isEmpty)
        #expect(sut.totals(from: .distantPast, through: .distantFuture, pricing: pricing).tokens.input == 1_000_000)
    }
}
