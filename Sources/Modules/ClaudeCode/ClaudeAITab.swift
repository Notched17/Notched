// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

/// What the AI tab reads: token usage from the logs, and the sessions the hooks report.
@MainActor
@Observable
final class ClaudeAIModel {
    var usage: ClaudeUsageSnapshot?
    var sessions: [ClaudeSessionsReducer.Snapshot] = []
}

/// The expanded island's "AI" tab (#62): today and this week, a 7-day bar
/// row, and the sessions that are working.
struct ClaudeAITabView: View {
    let model: ClaudeAIModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let usage = model.usage {
                HStack(alignment: .top, spacing: 16) {
                    StatBlock(title: "Today", totals: usage.today)
                    StatBlock(title: "This week", totals: usage.week)
                    DayBars(days: usage.days).frame(maxWidth: .infinity)
                }
                SessionsLine(hooked: model.sessions, fromLogs: usage.activeSessions)
                Text(verbatim: footnote(usage))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading Claude Code logs…").font(IslandFont.subtitle).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(.horizontal, 4)
    }

    private func footnote(_ usage: ClaudeUsageSnapshot) -> String {
        var parts = ["≈ estimated at API prices"]
        if usage.week.unpricedTokens > 0 { parts.append("some models unpriced") }
        if usage.skippedLines > 0 { parts.append("\(usage.skippedLines) unreadable") }
        return parts.joined(separator: " · ")
    }
}

private struct StatBlock: View {
    let title: String
    let totals: UsageTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            Text(verbatim: "≈ " + totals.cost.formatted(.currency(code: "USD")))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(verbatim: Self.compact(totals.tokens.total) + " tokens")
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): about \(totals.cost.formatted(.currency(code: "USD"))), \(Self.compact(totals.tokens.total)) tokens")
    }

    static func compact(_ count: Int) -> String {
        switch count {
        case 1_000_000...: String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...: String(format: "%.0fK", Double(count) / 1_000)
        default: String(count)
        }
    }
}

private struct DayBars: View {
    let days: [DayTotal]

    var body: some View {
        let peak = max(days.map(\.totals.tokens.total).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days) { day in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ClaudePresentation.tint.opacity(day.totals.tokens.total == 0 ? 0.2 : 0.9))
                        .frame(width: 10, height: max(3, 34 * CGFloat(day.totals.tokens.total) / CGFloat(peak)))
                    Text(day.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.day.formatted(.dateTime.weekday(.wide))): \(StatBlock.compact(day.totals.tokens.total)) tokens")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct SessionsLine: View {
    let hooked: [ClaudeSessionsReducer.Snapshot]
    let fromLogs: [ClaudeUsageSnapshot.ActiveSession]

    /// The sessions to list: the hooks' view if there is one, else what the logs show.
    private var lines: [(name: String, detail: String)] {
        if hooked.isEmpty {
            return fromLogs.prefix(2).map { (name: $0.project, detail: "active") }
        }
        return hooked.prefix(2).map { (name: $0.displayName, detail: ClaudePresentation.headline($0.phase)) }
    }

    var body: some View {
        if lines.isEmpty {
            Text("No active sessions").font(IslandFont.subtitle).foregroundStyle(.white.opacity(0.5))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        Circle().fill(ClaudePresentation.tint).frame(width: 6, height: 6)
                        Text(verbatim: line.name).font(IslandFont.subtitle).lineLimit(1)
                        Text(verbatim: line.detail).font(IslandFont.subtitle).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
