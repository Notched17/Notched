// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Home's list of every activity (ISLAND-BEHAVIOR.md §6): live ones (click to
/// open their page), hidden ones (click to show again) and recently ended ones.
struct ActivityListView: View {
    let model: IslandViewModel
    @State private var overflows = false

    var body: some View {
        let activities = model.activities
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if !activities.visible.isEmpty {
                    section("Live") {
                        ForEach(activities.visible) { record in
                            ActivityRow(record: record, detail: nil) {
                                withAnimation(Motion.content) { model.selectedPage = .activity(record.id) }
                            }
                        }
                    }
                }
                if !activities.hidden.isEmpty {
                    section("Hidden") {
                        ForEach(activities.hidden) { record in
                            ActivityRow(record: record, detail: "Show") { activities.unhide(record.id) }
                        }
                    }
                }
                if !activities.recent.isEmpty {
                    section("Recent") {
                        ForEach(activities.recent) { record in
                            ActivityRow(record: record, detail: endedText(record)) { activities.dismissRecent(record.id) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height > geometry.containerSize.height + 1
        } action: { _, overflowing in
            overflows = overflowing
        }
        // When there's more to scroll to, the last visible row fades out
        // rather than being cut off.
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .black.opacity(overflows ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
            }
        }
        // Leaves room under the list for the page indicator and the bottom margin.
        .frame(maxHeight: IslandMetrics.expandedMaxContentHeight - 40)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            rows()
        }
    }

    private func endedText(_ record: ActivityRecord) -> String {
        guard case .ended(let dismissAt) = record.state else { return "Ended" }
        let endedAt = dismissAt.addingTimeInterval(-model.activities.configuration.recentRetention.timeInterval)
        let minutes = max(Int(Date().timeIntervalSince(endedAt) / 60), 0)
        return minutes < 1 ? "Ended just now" : "Ended \(minutes) min ago"
    }
}

/// One activity in the list: its compact leading glyph in a concentric tile,
/// its description, and a detail or its compact trailing value.
private struct ActivityRow: View {
    let record: ActivityRecord
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                record.activity.presentation.compactLeading.view()
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08), in: ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true))
                Text(record.activity.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: Spacing.s)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let trailing = record.activity.presentation.compactTrailing {
                    trailing.view()
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.islandMode, .compact)
        // VoiceOver reads the activity's full description, plus the row's detail.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.activity.accessibilityLabel)
        .accessibilityValue(detail ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// Subtle dots under the expanded island's content: one per page.
struct PageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == current ? 0.85 : 0.28))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
