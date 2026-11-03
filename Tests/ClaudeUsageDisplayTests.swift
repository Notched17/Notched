// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import Notched

/// What the usage tab shows, worked out from the snapshot.
@Suite("ClaudeUsageDisplay")
struct ClaudeUsageDisplayTests {
    private func model(_ name: String, tokens: Int, cost: Double = 0) -> ModelTotal {
        ModelTotal(model: name, totals: UsageTotals(tokens: TokenCounts(input: tokens, output: 0, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0), cost: cost))
    }

    private func day(_ offset: Int, tokens: Int, cost: Double) -> DayTotal {
        DayTotal(day: Date(timeIntervalSinceReferenceDate: Double(offset) * 86_400),
                 totals: UsageTotals(tokens: TokenCounts(input: tokens, output: 0, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0), cost: cost))
    }

    @Test("Model names fold into their family")
    func families() {
        #expect(ClaudeUsageDisplay.family("claude-opus-4-5-20260101") == "Opus")
        #expect(ClaudeUsageDisplay.family("claude-sonnet-5-5") == "Sonnet")
        #expect(ClaudeUsageDisplay.family("claude-haiku-5-5") == "Haiku")
        #expect(ClaudeUsageDisplay.family("mystery-1") == "mystery-1")
        #expect(ClaudeUsageDisplay.family("") == "Other")
    }

    @Test("Shares add up, biggest first, versions of one family together")
    func shares() {
        let result = ClaudeUsageDisplay.shares([
            model("claude-opus-4-5", tokens: 300), model("claude-opus-4-1", tokens: 300),
            model("claude-sonnet-5-5", tokens: 300), model("claude-haiku-5-5", tokens: 100),
        ])
        #expect(result.map(\.name) == ["Opus", "Sonnet", "Haiku"])
        #expect(result.map(\.fraction) == [0.6, 0.3, 0.1])
    }

    @Test("More than three families leave the rest as Other")
    func other() {
        let result = ClaudeUsageDisplay.shares([
            model("claude-opus-4-5", tokens: 400), model("claude-sonnet-5-5", tokens: 300), model("claude-haiku-5-5", tokens: 200),
            model("alpha", tokens: 60), model("beta", tokens: 40),
        ])
        #expect(result.map(\.name) == ["Opus", "Sonnet", "Haiku", "Other"])
        #expect(abs(result.last!.fraction - 0.1) < 0.0001)
    }

    @Test("No usage, no shares")
    func empty() {
        #expect(ClaudeUsageDisplay.shares([]).isEmpty)
        #expect(ClaudeUsageDisplay.shares([model("claude-opus-4-5", tokens: 0)]).isEmpty)
    }

    @Test("Bars follow cost, the biggest day full height, an empty day a stub")
    func bars() {
        let days = [day(1, tokens: 10, cost: 1), day(2, tokens: 5, cost: 4), day(3, tokens: 0, cost: 0)]
        let fractions = ClaudeUsageDisplay.barFractions(days)
        #expect(fractions == [0.25, 1.0, 0.08])
    }

    @Test("With no prices the bars follow tokens instead")
    func barsWithoutPrices() {
        let days = [day(1, tokens: 100, cost: 0), day(2, tokens: 50, cost: 0)]
        #expect(ClaudeUsageDisplay.barValues(days) == [100, 50])
        #expect(ClaudeUsageDisplay.barFractions(days) == [1.0, 0.5])
    }

    @Test("A week with nothing in it draws stubs, not a crash")
    func allZero() {
        #expect(ClaudeUsageDisplay.barFractions([day(1, tokens: 0, cost: 0)]) == [0.08])
        #expect(ClaudeUsageDisplay.barFractions([]).isEmpty)
    }

    @Test("Token counts are short")
    func tokens() {
        #expect(ClaudeUsageDisplay.compactTokens(999) == "999")
        #expect(ClaudeUsageDisplay.compactTokens(340_000) == "340K")
        #expect(ClaudeUsageDisplay.compactTokens(4_100_000) == "4.1M")
    }
}
