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

/// What the usage tab says, worked out from the snapshot. Pure.
enum ClaudeUsageDisplay {
    struct ModelShare: Equatable, Sendable, Identifiable {
        var name: String
        /// 0…1 of the week's tokens.
        var fraction: Double
        var id: String { name }
    }

    /// "claude-opus-4-5-20260101" → "Opus"; unknown names are shown as they are.
    static func family(_ model: String) -> String {
        let lowered = model.lowercased()
        for name in ["opus", "sonnet", "haiku"] where lowered.contains(name) { return name.capitalized }
        return model.isEmpty ? "Other" : model
    }

    /// The week's tokens by model family, biggest first: the top three, the rest as "Other".
    static func shares(_ models: [ModelTotal], limit: Int = 3) -> [ModelShare] {
        var byFamily: [String: Int] = [:]
        for model in models { byFamily[family(model.model), default: 0] += model.totals.tokens.total }
        let total = byFamily.values.reduce(0, +)
        guard total > 0 else { return [] }
        let sorted = byFamily.filter { $0.value > 0 }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        var shares = sorted.prefix(limit).map { ModelShare(name: $0.key, fraction: Double($0.value) / Double(total)) }
        let rest = sorted.dropFirst(limit).reduce(0) { $0 + $1.value }
        if rest > 0 { shares.append(ModelShare(name: "Other", fraction: Double(rest) / Double(total))) }
        return shares
    }

    /// The value each day's bar is drawn from: its cost, or its tokens when nothing in the week has a price.
    static func barValues(_ days: [DayTotal]) -> [Double] {
        let anyCost = days.contains { $0.totals.cost > 0 }
        return days.map { anyCost ? $0.totals.cost : Double($0.totals.tokens.total) }
    }

    /// 0…1 bar heights against the biggest day, with a floor so an empty day still shows.
    static func barFractions(_ days: [DayTotal], floor: Double = 0.08) -> [Double] {
        let values = barValues(days)
        let peak = max(values.max() ?? 0, .leastNonzeroMagnitude)
        return values.map { value in value <= 0 ? floor : max(floor, value / peak) }
    }

    static func money(_ cost: Double) -> String { cost.formatted(.currency(code: "USD")) }

    static func compactTokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...: String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...: String(format: "%.0fK", Double(count) / 1_000)
        default: String(count)
        }
    }
}

/// The row beside the camera housing: the tab's name on the left, today's cost on the right.
struct ClaudeUsageHeaderLeading: View {
    var body: some View {
        HStack(spacing: 6) {
            BrandTile(symbol: "chart.bar.fill", tint: ClaudePresentation.tint, filled: true)
            Text("Usage").font(.system(size: 13, weight: .semibold))
        }
    }
}

struct ClaudeUsageHeaderTrailing: View {
    let model: ClaudeAIModel

    var body: some View {
        if let usage = model.usage {
            HStack(spacing: 5) {
                Text(verbatim: ClaudeUsageDisplay.money(usage.today.cost))
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("today").font(.system(size: 11)).dimmedText(0.7)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The expanded island's usage tab (#62): this week's cost and its days, the
/// split by model, and the sessions that are working. Today's cost is in the
/// row beside the camera housing.
struct ClaudeAITabView: View {
    let model: ClaudeAIModel
    @Environment(\.tabHeaderIsBesideNotch) private var headerIsBeside

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let usage = model.usage {
                HStack(alignment: .top, spacing: 8) {
                    WeekCard(usage: usage).frame(maxWidth: .infinity)
                    ModelsCard(shares: ClaudeUsageDisplay.shares(usage.models)).frame(width: 150)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .center, spacing: 8) {
                    SessionChips(hooked: model.sessions, fromLogs: usage.activeSessions)
                    Spacer(minLength: 4)
                    Text(verbatim: footnote(usage))
                        .font(.system(size: 10))
                        .dimmedText(0.7)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading Claude Code logs…").font(IslandFont.subtitle).dimmedText(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func footnote(_ usage: ClaudeUsageSnapshot) -> String {
        // No price table at all: say so, rather than a $0.00 that looks like a real estimate.
        var parts: [String] = []
        // Without the notch row, today's cost has no home of its own.
        if !headerIsBeside, usage.pricingUpdated != nil { parts.append("Today \(ClaudeUsageDisplay.money(usage.today.cost))") }
        parts.append(usage.pricingUpdated == nil ? "price table not found" : "≈ estimated at API prices")
        if usage.week.unpricedTokens > 0 { parts.append("some models unpriced") }
        if usage.skippedLines > 0 { parts.append("\(usage.skippedLines) unreadable") }
        return parts.joined(separator: " · ")
    }
}

private let cardFill = Color.white.opacity(0.06)

/// This week's cost as the big number, with a bar for each day.
private struct WeekCard: View {
    let usage: ClaudeUsageSnapshot

    var body: some View {
        let fractions = ClaudeUsageDisplay.barFractions(usage.days)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.system(size: 11)).dimmedText(0.7)
                Spacer(minLength: 4)
                Text(verbatim: ClaudeUsageDisplay.compactTokens(usage.week.tokens.total) + " tokens")
                    .font(.system(size: 11)).monospacedDigit().dimmedText(0.7)
            }
            Text(verbatim: "≈ " + ClaudeUsageDisplay.money(usage.week.cost))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(usage.days.enumerated()), id: \.element.id) { index, day in
                    let isToday = index == usage.days.count - 1
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(ClaudePresentation.tint.opacity(isToday ? 1 : 0.45))
                            .frame(height: max(3, 40 * fractions[index]))
                        Text(day.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? Color.white : Color.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.day.formatted(.dateTime.weekday(.wide))): about \(ClaudeUsageDisplay.money(day.totals.cost)), \(ClaudeUsageDisplay.compactTokens(day.totals.tokens.total)) tokens")
                }
            }
            .frame(height: 56, alignment: .bottom)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardFill, in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Where the week's tokens went, by model family.
private struct ModelsCard: View {
    let shares: [ClaudeUsageDisplay.ModelShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("By model").font(.system(size: 11)).dimmedText(0.7)
            if shares.isEmpty {
                Text("No usage yet").font(IslandFont.subtitle).dimmedText(0.7)
            }
            ForEach(shares) { share in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(verbatim: share.name).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: share.fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 11)).monospacedDigit().dimmedText(0.7)
                    }
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule().fill(ClaudePresentation.tint).frame(width: max(3, proxy.size.width * share.fraction))
                            }
                        }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardFill, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// Up to two sessions as small chips: the hooks' view if there is one, else what the logs show.
private struct SessionChips: View {
    let hooked: [ClaudeSessionsReducer.Snapshot]
    let fromLogs: [ClaudeUsageSnapshot.ActiveSession]

    private struct Chip: Identifiable {
        let id: String
        let name: String
        let detail: String
        let tint: Color
    }

    private var chips: [Chip] {
        if hooked.isEmpty {
            return fromLogs.prefix(2).map { Chip(id: $0.id, name: $0.project, detail: "active", tint: ClaudePresentation.tint) }
        }
        return hooked.prefix(2).map { snapshot in
            let tint: Color = switch snapshot.phase {
            case .waitingForApproval: .orange
            case .finished: .green
            case .idle: .gray
            default: ClaudePresentation.tint
            }
            return Chip(id: snapshot.sessionID, name: snapshot.displayName, detail: ClaudePresentation.expandedTitle(snapshot.phase).replacingOccurrences(of: "…", with: "").lowercased(), tint: tint)
        }
    }

    var body: some View {
        if chips.isEmpty {
            Text("No active sessions").font(IslandFont.subtitle).dimmedText(0.7)
        } else {
            HStack(spacing: 6) {
                ForEach(chips) { chip in
                    HStack(spacing: 6) {
                        Circle().fill(chip.tint).frame(width: 6, height: 6)
                        Text(verbatim: "\(chip.name) · \(chip.detail)").font(.system(size: 11)).lineLimit(1)
                    }
                    .padding(.leading, 7)
                    .padding(.trailing, 9)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: .capsule)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
