// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Made-up activities and tabs for the layout editor's preview, standing in for
/// the real modules so the preview works whatever is switched on. Each sample
/// belongs to the module id it stands for, so the ranking, pins and
/// "Show in Compact" choices apply to it exactly as they do to the real one.
@MainActor
enum LayoutPreviewSamples {
    private struct Sample {
        var id: ActivityID
        var module: ModuleID
        var kind: ActivityKind
        var title: String
        var symbol: String
        var value: String
        var tint: Color
        var relevance: Double
    }

    private static let samples: [Sample] = [
        Sample(id: "preview.media", module: "media", kind: .media, title: "Now Playing", symbol: "music.note", value: "♪", tint: .pink, relevance: 10),
        Sample(id: "preview.timer", module: "timers", kind: .live, title: "Timer", symbol: "timer", value: "4:32", tint: .orange, relevance: 20),
        Sample(id: "preview.calendar", module: "calendar", kind: .live, title: "Stand-up", symbol: "calendar", value: "9m", tint: .blue, relevance: 30),
        Sample(id: "preview.weather", module: "weather", kind: .passive, title: "Weather", symbol: "cloud.sun.fill", value: "14°", tint: .cyan, relevance: 0),
    ]

    static let previewModule: ModuleID = "layout.preview"

    static func makeCoordinator() -> ActivityCoordinator {
        let coordinator = ActivityCoordinator()
        for sample in samples { coordinator.post(activity(for: sample)) }
        return coordinator
    }

    /// The tabs the preview shows: one stand-in for each tab the editor lists.
    static func setTabs(on coordinator: ActivityCoordinator, tabs: [LayoutCatalogue.TabInfo]) {
        coordinator.setTabs(tabs.enumerated().map { index, info in
            IslandTab(id: info.id, moduleID: previewModule, title: info.title, symbol: info.symbol, order: index) {
                Label(info.title, systemImage: info.symbol)
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }, from: previewModule)
    }

    private static func activity(for sample: Sample) -> LiveActivity {
        LiveActivity(
            id: sample.id, moduleID: sample.module, kind: sample.kind, title: sample.title, relevance: sample.relevance,
            keylineTint: sample.tint, accessibilityLabel: "\(sample.title), \(sample.value)", staleNote: nil,
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { Image(systemName: sample.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(sample.tint) },
                compactTrailing: IslandRegion { Text(sample.value).font(IslandFont.compact).monospacedDigit().foregroundStyle(sample.tint) },
                minimal: IslandRegion { Image(systemName: sample.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(sample.tint) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        IslandTile { Image(systemName: sample.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(sample.tint) }
                    },
                    trailing: ExpandedRegion { Text(sample.value).font(IslandFont.hero).monospacedDigit().foregroundStyle(sample.tint) },
                    bottom: ExpandedRegion { Text(sample.title).font(IslandFont.title).frame(maxWidth: .infinity, alignment: .leading) }
                )
            )
        )
    }
}
