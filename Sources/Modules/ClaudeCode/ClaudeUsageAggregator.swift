// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct TokenCounts: Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cacheRead = 0

    var total: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }
    var cache: Int { cacheWrite5m + cacheWrite1h + cacheRead }

    static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
                    cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m, cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
                    cacheRead: lhs.cacheRead + rhs.cacheRead)
    }

    init(input: Int = 0, output: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    init(_ record: UsageRecord) {
        self.init(input: record.input, output: record.output, cacheWrite5m: record.cacheWrite5m,
                  cacheWrite1h: record.cacheWrite1h, cacheRead: record.cacheRead)
    }
}

struct UsageTotals: Equatable, Sendable {
    var tokens = TokenCounts()
    /// Estimated cost of the models that have a price.
    var cost = 0.0
    /// Tokens of models without a price, which the cost leaves out.
    var unpricedTokens = 0
}

struct DayTotal: Equatable, Sendable, Identifiable {
    var day: Date
    var totals: UsageTotals
    var id: Date { day }
}

struct ModelTotal: Equatable, Sendable, Identifiable {
    var model: String
    var totals: UsageTotals
    var id: String { model }
}

/// Sums usage by local calendar day and model, ignoring repeats of the same
/// response. Pure.
struct ClaudeUsageAggregator: Sendable {
    private struct Key: Hashable {
        let day: Date
        let model: String
    }

    private let calendar: Calendar
    private var seen: Set<String> = []
    private var buckets: [Key: TokenCounts] = [:]
    /// How many days of history to keep.
    static let keptDays = 8

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// False if this response was already counted.
    @discardableResult
    mutating func add(_ record: UsageRecord) -> Bool {
        guard seen.insert(record.dedupeKey).inserted else { return false }
        let key = Key(day: calendar.startOfDay(for: record.timestamp), model: record.model)
        buckets[key, default: TokenCounts()] = (buckets[key] ?? TokenCounts()) + TokenCounts(record)
        return true
    }

    /// Forgets days older than the kept window (and their dedupe keys on rebuild).
    mutating func prune(now: Date) {
        let cutoff = calendar.date(byAdding: .day, value: -(Self.keptDays - 1), to: calendar.startOfDay(for: now)) ?? now
        buckets = buckets.filter { $0.key.day >= cutoff }
    }

    var isEmpty: Bool { buckets.isEmpty }

    func totals(from first: Date, through last: Date, pricing: ClaudePricing) -> UsageTotals {
        var result = UsageTotals()
        for (key, tokens) in buckets where key.day >= first && key.day <= last {
            result.tokens = result.tokens + tokens
            if let cost = pricing.cost(of: tokens, model: key.model) {
                result.cost += cost
            } else {
                result.unpricedTokens += tokens.total
            }
        }
        return result
    }

    func today(now: Date, pricing: ClaudePricing) -> UsageTotals {
        let start = calendar.startOfDay(for: now)
        return totals(from: start, through: start, pricing: pricing)
    }

    /// The last 7 days, including today.
    func week(now: Date, pricing: ClaudePricing) -> UsageTotals {
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        return totals(from: start, through: end, pricing: pricing)
    }

    /// One entry per day for the last 7 days, oldest first, zero days included.
    func daily(now: Date, pricing: ClaudePricing) -> [DayTotal] {
        let end = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end).map { day in
                DayTotal(day: day, totals: totals(from: day, through: day, pricing: pricing))
            }
        }
    }

    /// Models used in the last 7 days, biggest first.
    func models(now: Date, pricing: ClaudePricing) -> [ModelTotal] {
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        var byModel: [String: TokenCounts] = [:]
        for (key, tokens) in buckets where key.day >= start && key.day <= end {
            byModel[key.model, default: TokenCounts()] = (byModel[key.model] ?? TokenCounts()) + tokens
        }
        return byModel.map { model, tokens in
            var totals = UsageTotals(tokens: tokens)
            if let cost = pricing.cost(of: tokens, model: model) { totals.cost = cost } else { totals.unpricedTokens = tokens.total }
            return ModelTotal(model: model, totals: totals)
        }
        .sorted { $0.totals.tokens.total > $1.totals.tokens.total }
    }
}
