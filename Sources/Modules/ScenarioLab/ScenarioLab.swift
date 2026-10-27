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
        case music, timer, call, agent, download

        var id: Self { self }

        var title: String {
            switch self {
            case .music: "Music"
            case .timer: "Timer"
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
    private var timerEnd = Date()
    private var timerStart = Date()
    private var starts: [Demo: Date] = [:]
    private var downloadProgress = 0.42
    private var script: Task<Void, Never>?

    init(activities: ActivityCoordinator) {
        self.activities = activities
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
        case .timer:
            timerStart = now
            timerEnd = now.addingTimeInterval(5 * 60)
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

    /// "Charging 80%": a short system banner.
    func showChargingBanner() {
        sink(.download).show(TransientBanner(
            id: "lab.charging",
            moduleID: Demo.download.moduleID,
            leading: IslandRegion {
                Label("Charging", systemImage: "bolt.fill")
                    .labelStyle(DemoBannerLabelStyle(tint: .green))
            },
            trailing: IslandRegion {
                HStack(spacing: 5) {
                    Text("80%").font(IslandFont.compact).monospacedDigit()
                    Image(systemName: "battery.75percent")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.green, .white.opacity(0.4))
                }
            },
            accessibilityLabel: "Charging, 80 percent"
        ))
    }

    /// "Timer done": an alerting update that expands the island.
    func alertTimerDone() {
        if activities.live.first(where: { $0.id == Demo.timer.activityID }) == nil { start(.timer) }
        timerEnd = Date()
        sink(.timer).post(timerActivity(done: true), alert: AlertRequest(sound: "Glass"))
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
                (2.5, { $0.start(.timer) }),
                (3, { $0.start(.download) }),
                (3, { $0.showChargingBanner() }),
                (3, { $0.setDownloadProgress(0.74) }),
                (2.5, { $0.start(.call) }),
                (6, { $0.perform(.end, on: .call) }),
                (2.5, { $0.setDownloadProgress(1) }),
                (1.5, { $0.perform(.end, on: .download) }),
                (2, { $0.alertTimerDone() }),
                (6, { $0.perform(.end, on: .timer) }),
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
        case .timer: timerActivity(done: false)
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

    private func timerActivity(done: Bool) -> LiveActivity {
        let end = timerEnd
        let start = timerStart
        let glyph = done ? "bell.fill" : "timer"
        return LiveActivity(
            id: Demo.timer.activityID, moduleID: Demo.timer.moduleID, kind: .live, title: done ? "Timer Done" : "Timer",
            keylineTint: DemoTimerStyle.tint,
            accessibilityLabel: done ? "Timer done" : "Timer, 5 minutes",
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: glyph)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DemoTimerStyle.tint)
                        .symbolEffect(.bounce, value: done)
                },
                compactTrailing: IslandRegion {
                    if done {
                        Text("Done").font(IslandFont.compact).foregroundStyle(DemoTimerStyle.tint)
                    } else {
                        DemoCountdown(end: end)
                    }
                },
                minimal: IslandRegion {
                    if done {
                        Image(systemName: "bell.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(DemoTimerStyle.tint)
                    } else {
                        DemoCountdown(end: end, font: IslandFont.minimal)
                    }
                },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        DemoTile {
                            Image(systemName: glyph)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(DemoTimerStyle.tint)
                        }
                    },
                    trailing: ExpandedRegion {
                        if done {
                            Text("Done").font(IslandFont.hero).foregroundStyle(DemoTimerStyle.tint)
                        } else {
                            DemoCountdown(end: end, font: IslandFont.hero)
                        }
                    },
                    bottom: ExpandedRegion {
                        if done {
                            VStack(alignment: .leading, spacing: Spacing.m) {
                                Text("Timer Done").font(IslandFont.title)
                                DemoTimerDone()
                            }
                        } else {
                            DemoTimerExpandedBottom(start: start, end: end)
                        }
                    }
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

/// A banner's leading label: tinted symbol, then white text.
struct DemoBannerLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            configuration.title
                .font(IslandFont.compact)
        }
    }
}
#endif
