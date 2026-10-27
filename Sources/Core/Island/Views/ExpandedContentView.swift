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
        ZStack(alignment: .top) {
            Group {
                if let record = model.expandedActivity {
                    ActivityExpandedView(record: record, housing: model.housingSize)
                } else {
                    HomeView(model: model)
                }
            }
            .id(pageKey)
            .transition(Motion.contentSwap)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                model.reportExpandedHeight(height, for: pageKey)
            }
        }
        .padding(.horizontal, model.contentHorizontalInset)
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
            if record.isStale {
                Label("Updating…", systemImage: "arrow.triangle.2.circlepath")
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

/// The expanded island with nothing live: time and controls beside the
/// camera housing, and a quiet note below.
struct HomeView: View {
    let model: IslandViewModel

    var body: some View {
        VStack(spacing: Spacing.s) {
            ExpandedHeaderView(model: model)
                .frame(height: model.headerHeight)
            IslandEmptyState()
                .padding(.top, Spacing.xxs)
        }
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
