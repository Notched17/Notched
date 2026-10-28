// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import SwiftUI

/// DEBUG-only demo activities that drive the real coordinator, so every
/// island behaviour (bubbles, swap, hide, stale, Recent, alerts, banners) can
/// be tried and screenshotted (ISLAND-BEHAVIOR.md; Debug ▸ Scenario Lab).
///
/// Each demo posts through its own `ActivitySink`, like a separate module,
/// so module scoping applies exactly as it will for real ones.
@MainActor
final class ScenarioLab {
    enum Demo: String, CaseIterable, Identifiable {
        case music, call, agent, download

        var id: Self { self }

        var title: String {
            switch self {
            case .music: "Music"
            case .call: "Call"
            case .agent: "Claude Code"
            case .download: "Download"
            }
        }

        var activityID: ActivityID { ActivityID("lab.\(rawValue)") }
        var moduleID: ModuleID { ModuleID("lab.\(rawValue)") }
    }

    enum Action: String, CaseIterable {
        case start, end, stale, hide, unhide, primary

        var title: String {
            switch self {
            case .start: "Start"
            case .end: "End"
            case .stale: "Make Stale"
            case .hide: "Hide"
            case .unhide: "Unhide"
            case .primary: "Make Primary"
            }
        }
    }

    private let activities: ActivityCoordinator
    /// Starts a real timer (Timers, when it's on): the Lab has no fake one.
    private let startTimer: @MainActor (TimeInterval) -> Void
    private var starts: [Demo: Date] = [:]
    private var downloadProgress = 0.42
    private var script: Task<Void, Never>?

    init(activities: ActivityCoordinator, startTimer: @escaping @MainActor (TimeInterval) -> Void = { _ in }) {
        self.activities = activities
        self.startTimer = startTimer
    }

    private func sink(_ demo: Demo) -> ActivitySink {
        ActivitySink(moduleID: demo.moduleID, coordinator: activities)
    }

    func perform(_ action: Action, on demo: Demo) {
        switch action {
        case .start: start(demo)
        case .end: sink(demo).end(demo.activityID)
        case .stale: post(demo, stale: true)
        case .hide: activities.hide(demo.activityID)
        case .unhide: activities.unhide(demo.activityID)
        case .primary: activities.makePrimary(demo.activityID)
        }
    }

    func start(_ demo: Demo) {
        let now = Date()
        starts[demo] = now
        switch demo {
        case .download:
            downloadProgress = 0.42
        default:
            break
        }
        post(demo)
    }

    func endAll() {
        script?.cancel()
        for demo in Demo.allCases { sink(demo).endAll() }
    }

    /// "Charging 80%": a short system banner, in the standard banner look.
    func showChargingBanner() {
        sink(.download).show(.standard(id: "lab.charging", moduleID: Demo.download.moduleID, content: BannerContent(
            label: "Charging", value: "80%", accessory: .battery(level: 80, isCharging: true, tint: .green)
        ), accessibilityLabel: "Charging, 80 percent"))
    }


    /// Sets the download's progress, ending it at 100%.
    func setDownloadProgress(_ progress: Double) {
        downloadProgress = min(max(progress, 0), 1)
        post(.download)
    }

    /// A scripted tour of the island's behaviour.
    func runFullDemo() {
        endAll()
        script = Task { [weak self] in
            let steps: [(Double, @MainActor (ScenarioLab) -> Void)] = [
                (0, { $0.start(.music) }),
                // A real 20 s timer: it ends, alerts and rings at the end of the tour.
                (2.5, { $0.startTimer(20) }),
                (3, { $0.start(.download) }),
                (3, { $0.showChargingBanner() }),
                (3, { $0.setDownloadProgress(0.74) }),
                (2.5, { $0.start(.call) }),
                (6, { $0.perform(.end, on: .call) }),
                (2.5, { $0.setDownloadProgress(1) }),
                (1.5, { $0.perform(.end, on: .download) }),
            ]
            for (delay, step) in steps {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                step(self)
            }
        }
    }

    // MARK: Activities

    private func post(_ demo: Demo, stale: Bool = false) {
        var activity = switch demo {
        case .music: musicActivity()
        case .call: callActivity()
        case .agent: agentActivity()
        case .download: downloadActivity()
        }
        if stale { activity.staleDate = Date().addingTimeInterval(-1) }
        sink(demo).post(activity)
    }

    private func started(_ demo: Demo) -> Date { starts[demo] ?? Date() }

    private func musicActivity() -> LiveActivity {
        let start = started(.music)
        return LiveActivity(
            id: Demo.music.activityID, moduleID: Demo.music.moduleID, kind: .media, title: "Golden Hour",
            keylineTint: DemoBars.tint,
            accessibilityLabel: "Golden Hour by Notched Demo, playing",
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { DemoArtwork(size: 20) },
                compactTrailing: IslandRegion { DemoBars(height: 14) },
                minimal: IslandRegion { DemoBars(height: 12, barWidth: 2) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion { DemoArtwork(size: 44) },
                    trailing: ExpandedRegion { DemoBars(height: 18, barWidth: 3) },
                    bottom: ExpandedRegion { DemoMusicExpandedBottom(start: start) }
                )
            )
        )
    }

    private func callActivity() -> LiveActivity {
        let start = started(.call)
        return LiveActivity(
            id: Demo.call.activityID, moduleID: Demo.call.moduleID, kind: .system, title: "Sam Rivera",
            isHideable: false,
            keylineTint: DemoCallStyle.tint,
            accessibilityLabel: "Call with Sam Rivera",
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DemoCallStyle.tint)
                },
                compactTrailing: IslandRegion { DemoElapsed(start: start, tint: DemoCallStyle.tint) },
                minimal: IslandRegion { DemoElapsed(start: start, font: IslandFont.minimal, tint: DemoCallStyle.tint) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion { DemoAvatar(size: 40) },
                    trailing: ExpandedRegion { DemoElapsed(start: start, font: IslandFont.title, tint: DemoCallStyle.tint) },
                    bottom: ExpandedRegion {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sam Rivera").font(IslandFont.title)
                                Text("FaceTime Audio").font(IslandFont.subtitle).foregroundStyle(.secondary)
                            }
                            DemoCallControls()
                        }
                    }
                )
            )
        )
    }

    private func agentActivity() -> LiveActivity {
        let start = started(.agent)
        return LiveActivity(
            id: Demo.agent.activityID, moduleID: Demo.agent.moduleID, kind: .live, title: "Claude Code",
            keylineTint: DemoAgentStyle.tint,
            accessibilityLabel: "Claude Code working on Notched",
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { DemoAgentGlyph(size: 14) },
                compactTrailing: IslandRegion { DemoElapsed(start: start) },
                minimal: IslandRegion { DemoAgentGlyph(size: 13) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion { DemoTile { DemoAgentGlyph(size: 18) } },
                    trailing: ExpandedRegion { DemoElapsed(start: start, font: IslandFont.title) },
                    bottom: ExpandedRegion { DemoAgentDetail() }
                )
            )
        )
    }

    private func downloadActivity() -> LiveActivity {
        let progress = downloadProgress
        return LiveActivity(
            id: Demo.download.activityID, moduleID: Demo.download.moduleID, kind: .live, title: "Golden Gate 4K.mov",
            keylineTint: DemoDownloadStyle.tint,
            accessibilityLabel: "Downloading Golden Gate 4K.mov, \(Int(progress * 100)) percent",
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: progress >= 1 ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DemoDownloadStyle.tint)
                        .contentTransition(.symbolEffect(.replace))
                },
                compactTrailing: IslandRegion { DemoPercent(progress: progress) },
                minimal: IslandRegion { DemoProgressRing(progress: progress, size: 17, lineWidth: 2.5) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        DemoTile {
                            Image(systemName: "film")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(DemoDownloadStyle.tint)
                        }
                    },
                    trailing: ExpandedRegion { DemoPercent(progress: progress, font: IslandFont.title) },
                    bottom: ExpandedRegion { DemoDownloadBottom(progress: progress) }
                )
            )
        )
    }
}

#endif
