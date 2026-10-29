// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Everything inside the expanded island: one activity laid out in its
/// regions around the camera housing, or Home when nothing is live. The
/// island's height follows the measured content (ISLAND-BEHAVIOR.md §4).
struct ExpandedContentView: View {
    let model: IslandViewModel

    var body: some View {
        let rect = model.islandRect(for: .expanded)
        let pageKey = model.expandedPageKey
        let pages = model.pages
        ZStack(alignment: .top) {
            VStack(spacing: Spacing.s) {
                Group {
                    if let tab = model.selectedModuleTab {
                        IslandTabContent(tab: tab)
                    } else if let record = model.expandedActivity {
                        ActivityExpandedView(record: record, housing: model.housingSize)
                    } else {
                        HomeView(model: model)
                    }
                }
                .id(pageKey)
                .transition(AnyTransition(.blurReplace).combined(with: .opacity))
                if model.showsTabBar {
                    // Page dots only mean something on the Island tab.
                    HStack(spacing: Spacing.m) {
                        if pages.count > 1, model.selectedModuleTab == nil {
                            PageIndicator(count: pages.count, current: pages.firstIndex(of: model.currentPage) ?? 0)
                        }
                        IslandTabBar(model: model, onSelect: model.onTabChanged)
                    }
                } else if pages.count > 1, model.activities.alert == nil {
                    PageIndicator(count: pages.count, current: pages.firstIndex(of: model.currentPage) ?? 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                model.reportExpandedHeight(height, for: pageKey)
            }
        }
        .padding(.horizontal, model.contentHorizontalInset)
        // Without a camera housing (the pill), keep content off the top edge
        // with the same margin as the sides.
        .padding(.top, model.expandedTopInset)
        .frame(width: rect.width, height: rect.height, alignment: .top)
        // Inner rounded shapes nest concentrically inside the island's bottom corners.
        .containerShape(.rect(cornerRadius: model.shapeMetrics.bottom, style: .continuous))
    }
}

/// One activity's expanded presentation.
struct ActivityExpandedView: View {
    let record: ActivityRecord
    let housing: CGSize

    var body: some View {
        let expanded = record.activity.presentation.expanded
        VStack(spacing: Spacing.xs) {
            ExpandedRegionsLayout(housing: housing, spacing: Spacing.s) {
                region(expanded.leading, role: .leading)
                region(expanded.trailing, role: .trailing)
                region(expanded.center, role: .center)
                region(expanded.bottom, role: .bottom)
            }
            if record.isStale, let note = record.activity.staleNote {
                Label(note.text, systemImage: note.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(record.activity.accessibilityLabel)
    }

    @ViewBuilder
    private func region(_ region: ExpandedRegion?, role: ExpandedRegionsGeometry.Role) -> some View {
        if let region {
            IslandRegionHost(revision: record.revision, isStale: record.isStale) {
                region.view()
            }
            .layoutValue(key: ExpandedRegionTag.self, value: ExpandedRegionTag.Value(
                role: role,
                priority: region.priority,
                belowIfTooWide: region.placement == .belowIfTooWide
            ))
        }
    }
}

/// The expanded island's Home page: time and controls beside the camera
/// housing, and below them every activity (or a quiet note when there are none).
struct HomeView: View {
    @Bindable var model: IslandViewModel

    var body: some View {
        let activities = model.activities
        VStack(spacing: Spacing.s) {
            ExpandedHeaderView(model: model)
                .frame(height: model.headerHeight)
            if !activities.homeActions.isEmpty {
                HomeActionsView(actions: activities.homeActions, openID: $model.openHomeAction)
            }
            if model.openHomeAction != nil {
                // The open panel has the room; the list is a click away on its pages.
                EmptyView()
            } else if activities.live.isEmpty && activities.recent.isEmpty {
                IslandEmptyState()
                    .padding(.top, Spacing.xxs)
            } else {
                ActivityListView(model: model)
            }
        }
        .onDisappear { model.openHomeAction = nil }
    }
}

/// The quiet placeholder shown when no activity is live.
struct IslandEmptyState: View {
    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("Nothing live right now")
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Turn on modules in Settings to see them here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
