// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Per-model prices in USD per million tokens, from a data file the user can
/// override. Everything built on it is labelled an estimate.
struct ClaudePricing: Equatable, Sendable {
    struct ModelPrice: Codable, Equatable, Sendable {
        var match: String
        var input: Double
        var output: Double
        var cacheWrite5m: Double
        var cacheWrite1h: Double
        var cacheRead: Double
    }

    private struct File: Codable {
        var version: Int
        var updated: String?
        var models: [ModelPrice]
    }

    var updated: String?
    var models: [ModelPrice]

    static let empty = ClaudePricing(updated: nil, models: [])

    static func decode(_ data: Data) -> ClaudePricing? {
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1 else { return nil }
        return ClaudePricing(updated: file.updated, models: file.models)
    }

    /// The user's override if it's valid, else the bundled table.
    static func load(bundle: Bundle = .main, overrideURL: URL = userOverrideURL) -> ClaudePricing {
        if let data = try? Data(contentsOf: overrideURL), let custom = decode(data) { return custom }
        if let url = bundle.url(forResource: "claude-pricing", withExtension: "json"),
           let data = try? Data(contentsOf: url), let table = decode(data) { return table }
        return .empty
    }

    static var userOverrideURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notched/claude-pricing.json")
    }

    /// The longest matching entry. A pattern ending in `*` matches any
    /// suffix; any other pattern must match exactly.
    func price(for model: String) -> ModelPrice? {
        let lowered = model.lowercased()
        return models
            .filter { entry in
                let pattern = entry.match.lowercased()
                return pattern.hasSuffix("*") ? lowered.hasPrefix(String(pattern.dropLast())) : lowered == pattern
            }
            .max { $0.match.count < $1.match.count }
    }

    func cost(of tokens: TokenCounts, model: String) -> Double? {
        guard let price = price(for: model) else { return nil }
        let perMillion = 1_000_000.0
        return (Double(tokens.input) * price.input + Double(tokens.output) * price.output
            + Double(tokens.cacheWrite5m) * price.cacheWrite5m + Double(tokens.cacheWrite1h) * price.cacheWrite1h
            + Double(tokens.cacheRead) * price.cacheRead) / perMillion
    }
}
