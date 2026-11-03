// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The expanded island's tab bar: a small segmented control of SF Symbols,
/// the selected one showing its name. It sits under the content, beside the
/// page dots. Every tab is shown, side by side (each segment is 30 pt wide,
/// plus one label).
struct IslandTabBar: View {
    let model: IslandViewModel
    /// The module tabs and the selection, read by the parent and passed in as
    /// values, so the bar redraws whenever the content does.
    let tabs: [IslandTab]
    let selected: String
    /// Called after the user picks a tab, for haptics.
    var onSelect: () -> Void = {}
    @Environment(\.islandSurfaceIsGlass) private var islandIsGlass

    private struct Segment: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let label: String
    }

    var body: some View {
        let segments = [Segment(id: ExpandedTabs.islandID, title: "Island", symbol: "circle.grid.2x2.fill",
                                label: "Island")]
            + tabs.map { Segment(id: $0.id, title: $0.title, symbol: $0.symbol, label: $0.accessibilityLabel) }
        // Side by side; if a set of tabs ever outgrows the island, the bar scrolls.
        ViewThatFits(in: .horizontal) {
            bar(segments)
            ScrollView(.horizontal) { bar(segments) }
                .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    private func bar(_ segments: [Segment]) -> some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                SegmentButton(
                    title: segment.title,
                    symbol: segment.symbol,
                    isSelected: segment.id == selected,
                    onGlassSurface: islandIsGlass,
                    accessibilityLabel: "\(segment.label), tab \(index + 1) of \(segments.count)"
                ) {
                    let moved = withAnimation(model.accessibility.reduceMotion ? Motion.reduced : Motion.content) {
                        model.selectTab(segment.id)
                    }
                    if moved { onSelect() }
                }
            }
        }
        .padding(Spacing.xxs)
        .background(.fill.quaternary, in: .capsule)
    }
}

private struct SegmentButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let onGlassSurface: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                if isSelected {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(0.9)))
                }
            }
            .padding(.horizontal, isSelected ? Spacing.s : Spacing.xs)
            .frame(minWidth: 30, minHeight: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background {
            if isSelected {
                Capsule().fill(.white.opacity(onGlassSurface ? 0.22 : 0.16))
            }
        }
        .help(title)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A module tab's content. Built only while the tab is selected, and told
/// when it appears and goes.
struct IslandTabContent: View {
    let tab: IslandTab

    var body: some View {
        tab.content.view()
            .foregroundStyle(.white)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tab.accessibilityLabel)
            .onAppear { tab.onVisibilityChange?(true) }
            .onDisappear { tab.onVisibilityChange?(false) }
    }
}

extension EnvironmentValues {
    /// A tab's title and key figure are drawn in the row beside the camera
    /// housing, so its body leaves them out.
    @Entry var tabHeaderIsBesideNotch = false
    /// Set while content may wrap around the camera housing (see `NotchWrap`).
    @Entry var notchWrap: NotchWrap?
}

/// Lets a tab's top content rise into the row beside the camera housing,
/// leaving the housing's width clear in the middle, so the island is shorter.
/// Only on a notched display with Notch Black (the black runs on from the
/// notch, so content beside it reads as part of it) and a wide enough
/// island for each side to hold something (Expanded size 110% or more).
struct NotchWrap: Equatable, Sendable {
    /// How far to pull the content up from where the tab would put it (points).
    var rise: CGFloat
    /// The clear width in the middle, for the camera housing.
    var gap: CGFloat

    static let minimumScale = 1.1
    /// Where the wrapped content starts, measured from the island's top edge.
    static let top: CGFloat = 6

    static func make(isNotch: Bool, theme: IslandTheme, scale: Double, headerHeight: CGFloat, notchGap: CGFloat) -> NotchWrap? {
        guard isNotch, theme == .notchBlack, scale >= minimumScale - 0.001 else { return nil }
        return NotchWrap(rise: headerHeight + IslandMetrics.expandedNotchGap - top, gap: notchGap)
    }
}
