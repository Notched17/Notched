// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Everything inside the expanded island: the header row and the primary
/// activity's regions. (Step 2 replaces the stack with the region layout.)
struct ExpandedContentView: View {
    let model: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            ExpandedHeaderView(model: model)
                .frame(height: model.headerHeight)
            Group {
                if let record = model.activities.primary {
                    let expanded = record.activity.presentation.expanded
                    VStack(spacing: Spacing.s) {
                        HStack {
                            expanded.leading?.view()
                            Spacer(minLength: 0)
                            expanded.trailing?.view()
                        }
                        expanded.center?.view()
                        expanded.bottom?.view()
                    }
                    .id(record.id)
                    .transition(Motion.contentSwap)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(record.activity.accessibilityLabel)
                } else {
                    IslandEmptyState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, model.contentHorizontalInset)
        .padding(.bottom, Spacing.l)
        .frame(width: model.islandRect(for: .expanded).width, height: model.islandRect(for: .expanded).height, alignment: .top)
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
