// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The expanded island's tab bar: a small segmented control of SF Symbols,
/// the selected one showing its name. It sits under the content, beside the
/// page dots, and stays well inside the island's width: at most five
/// segments, each 30 pt wide, plus one label.
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
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
