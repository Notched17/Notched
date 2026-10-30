// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What one assistant response cost, from Claude Code's session log.
struct UsageRecord: Equatable, Sendable {
    var messageID: String
    var requestID: String?
    var timestamp: Date
    var model: String
    var input: Int
    var output: Int
    var cacheWrite5m: Int
    var cacheWrite1h: Int
    var cacheRead: Int
    var sessionID: String?
    var cwd: String?

    /// One response is written once per content block, with the same usage on
    /// each line; this identifies it (the way ccusage dedupes).
    var dedupeKey: String { messageID + "|" + (requestID ?? "") }
}

/// Reads one line of a Claude Code session log (`~/.claude/projects/**/*.jsonl`).
/// Every field is optional because the format isn't documented and drifts:
/// a line it can't use is skipped, never fatal.
enum ClaudeUsageParser {
    private static let needle = Data("\"output_tokens\"".utf8)
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(line: Data) -> UsageRecord? {
        // Most lines (prompts, tool results, titles) have no usage; skip them without decoding.
        guard line.range(of: needle) != nil else { return nil }
        var data = line
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        guard let object = try? JSONSerialization.jsonObject(with: data), let json = object as? [String: Any] else { return nil }
        if let type = json["type"] as? String, type != "assistant" { return nil }
        guard let message = json["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
              let messageID = message["id"] as? String,
              let stamp = json["timestamp"] as? String, let timestamp = withFraction.date(from: stamp) ?? plain.date(from: stamp) else { return nil }
        let model = (message["model"] as? String) ?? "unknown"
        // Claude Code's own placeholder messages cost nothing.
        guard model != "<synthetic>" else { return nil }

        let totalCacheWrite = count(usage["cache_creation_input_tokens"])
        var write5m = totalCacheWrite
        var write1h = 0
        if let split = usage["cache_creation"] as? [String: Any] {
            write5m = count(split["ephemeral_5m_input_tokens"])
            write1h = count(split["ephemeral_1h_input_tokens"])
            // Anything the split doesn't account for is billed as a 5-minute write.
            if write5m + write1h < totalCacheWrite { write5m += totalCacheWrite - write5m - write1h }
        }
        return UsageRecord(
            messageID: messageID,
            requestID: (json["requestId"] as? String) ?? (json["request_id"] as? String),
            timestamp: timestamp,
            model: model,
            input: count(usage["input_tokens"]),
            output: count(usage["output_tokens"]),
            cacheWrite5m: write5m,
            cacheWrite1h: write1h,
            cacheRead: count(usage["cache_read_input_tokens"]),
            sessionID: json["sessionId"] as? String,
            cwd: json["cwd"] as? String
        )
    }

    /// A non-negative whole number from whatever JSON gave (an int, a double, or nothing).
    private static func count(_ value: Any?) -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return 0 }
        let double = number.doubleValue
        guard double.isFinite, double > 0 else { return 0 }
        return Int(min(double, 1e12))
    }
}
