// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

extension ActivityTint {
    var color: Color {
        switch self {
        case .white: .white
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .yellow: .yellow
        case .purple: .purple
        case .pink: .pink
        case .teal: .teal
        case .gray: .gray
        }
    }
}

/// Turns a validated API activity into island regions. All text is shown
/// verbatim (never as markup), and every activity says who posted it, so a
/// client can't pass itself off as the system.
@MainActor
enum ActivityAPIPresentation {
    static let fallbackSymbol = "app.badge"

    static func symbolName(_ requested: String?, template: ActivityTemplate) -> String {
        if let requested, NSImage(systemSymbolName: requested, accessibilityDescription: nil) != nil { return requested }
        switch template {
        case .status: return fallbackSymbol
        case .progress: return "chart.bar.fill"
        case .countdown: return "timer"
        }
    }

    static func activity(key: ActivityKey, entry: ActivityAPIReducer.Entry, moduleID: ModuleID) -> LiveActivity {
        let spec = entry.spec
        let tint = spec.tint.color
        let symbol = symbolName(spec.symbol, template: spec.template)
        let url = spec.openURL
        let label = [spec.title, spec.subtitle, "from \(entry.clientName)"].compactMap { $0 }.joined(separator: ", ")
        return LiveActivity(
            id: activityID(key),
            moduleID: moduleID,
            kind: spec.isPassive ? .passive : .live,
            title: spec.title,
            relevance: 0.3,
            staleDate: entry.updatedAt.addingTimeInterval(spec.staleAfter),
            keylineTint: tint,
            accessibilityLabel: label,
            openAction: url.map { url in { NSWorkspace.shared.open(url) } },
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                },
                compactTrailing: trailingRegion(spec, tint: tint),
                minimal: IslandRegion { MinimalGlyph(spec: spec, symbol: symbol, tint: tint) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        IslandTile {
                            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                        }
                        .padding(.top, 6)
                    },
                    trailing: ExpandedRegion {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: spec.title).font(IslandFont.title).lineLimit(1)
                            if let subtitle = spec.subtitle {
                                Text(verbatim: subtitle).font(IslandFont.subtitle).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                            }
                            Text(verbatim: "from \(entry.clientName)").font(IslandFont.subtitle).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                        }
                    },
                    bottom: ExpandedRegion { ExpandedBottom(spec: spec, tint: tint) }
                )
            )
        )
    }

    static func activityID(_ key: ActivityKey) -> ActivityID { ActivityID("activityapi.\(key.clientID).\(key.id)") }

    private static func trailingRegion(_ spec: ActivitySpec, tint: Color) -> IslandRegion? {
        switch spec.template {
        case .status:
            guard let text = spec.trailing else { return nil }
            return IslandRegion { Text(verbatim: text).font(IslandFont.compact).monospacedDigit().lineLimit(1) }
        case .progress:
            let value = spec.progress ?? 0
            return IslandRegion { ProgressRing(value: value, tint: tint, lineWidth: 2.5).frame(width: 18, height: 18) }
        case .countdown:
            guard let endsAt = spec.endsAt else { return nil }
            return IslandRegion {
                Text(timerInterval: Date.now...max(endsAt, .now), countsDown: true)
                    .font(IslandFont.compact).monospacedDigit().lineLimit(1)
            }
        }
    }
}

private struct MinimalGlyph: View {
    let spec: ActivitySpec
    let symbol: String
    let tint: Color

    var body: some View {
        switch spec.template {
        case .progress:
            ProgressRing(value: spec.progress ?? 0, tint: tint, lineWidth: 2.5).frame(width: 18, height: 18)
        case .countdown:
            if let endsAt = spec.endsAt {
                WidthCap(maxWidth: IslandMetrics.bubbleMaxWidth - 2 * IslandMetrics.bubblePadding) {
                    Text(timerInterval: Date.now...max(endsAt, .now), countsDown: true)
                        .font(IslandFont.minimal).monospacedDigit().minimumScaleFactor(0.7)
                }
            }
        case .status:
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
        }
    }
}

struct ProgressRing: View {
    let value: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: value)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

private struct ExpandedBottom: View {
    let spec: ActivitySpec
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if spec.template == .progress, let progress = spec.progress {
                ProgressView(value: progress).tint(tint)
                    .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            }
            if spec.template == .countdown, let endsAt = spec.endsAt {
                Text(timerInterval: Date.now...max(endsAt, .now), countsDown: true)
                    .font(IslandFont.hero).monospacedDigit()
            }
            if let url = spec.openURL {
                Button("Open") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
