// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The expanded island's top row: time and date on the left of the notch,
/// glass controls on the right. Nothing is placed under the camera housing.
struct ExpandedHeaderView: View {
    let model: IslandViewModel

    var body: some View {
        HStack(spacing: 0) {
            IslandClock()
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: model.headerNotchGap)
            IslandHeaderControls(model: model)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Time and date, stacked so they fit beside the camera housing. Re-renders
/// once a minute, and only while visible.
struct IslandClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(context.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }
}

/// Settings and Pause, as glass buttons grouped so their glass can blend.
struct IslandHeaderControls: View {
    let model: IslandViewModel

    var body: some View {
        GlassEffectContainer(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                IslandIconButton(symbol: "gearshape.fill", label: "Settings", onGlassSurface: model.surfaceIsGlass) {
                    model.actions.openSettings()
                }
                IslandIconButton(symbol: "pause.fill", label: "Pause island", onGlassSurface: model.surfaceIsGlass) {
                    model.actions.pauseIsland()
                }
            }
        }
    }
}
