// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

/// Battery (#26): charging, full and low-battery banners, and an opt-in
/// charging activity. A thin shell around `BatteryReducer`: IOKit's power
/// notifications become snapshots, and the reducer's effects become banners.
@MainActor
final class BatteryModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "battery",
        name: "Battery",
        symbol: "battery.75percent",
        summary: "A short banner when you plug in or unplug, when the battery is full, and when it runs low.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: true
    )
    static let activityID: ActivityID = "battery.charging"

    /// Macs without a battery never see the module. Read once: a Mac's
    /// internal battery doesn't come and go.
    static let isAvailable = PowerSourceMonitor.read().hasBattery

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(BatterySettingsPane(settings: context.settings.battery))
    }

    let model = BatteryModel()
    private let context: ModuleContext
    private let settings: BatterySettings
    private let monitor = PowerSourceMonitor()
    private let wakeTimer = OneShotTimer()
    private var reducer = BatteryReducer()
    private var isRunning = false

    init(context: ModuleContext) {
        self.context = context
        settings = context.settings.battery
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reducer = BatteryReducer(preferences: settings.preferences)
        wakeTimer.action = { [weak self] in self?.send(.tick) }
        monitor.onChange = { [weak self] snapshot in self?.receive(snapshot) }
        observeSettings()
        monitor.start()
    }

    func stop() {
        isRunning = false
        monitor.stop()
        monitor.onChange = { _ in }
        wakeTimer.schedule(at: nil)
        context.activities.endAll()
        model.snapshot = nil
    }

    #if DEBUG
    /// Feeds a made-up reading through the real reducer (Scenario Lab), for
    /// states that can't be produced on demand: full, low.
    func simulate(_ snapshot: PowerSnapshot) {
        receive(snapshot)
    }
    #endif

    private func receive(_ snapshot: PowerSnapshot) {
        guard isRunning else { return }
        model.snapshot = snapshot
        send(.snapshot(snapshot))
    }

    private func observeSettings() {
        guard isRunning else { return }
        let preferences = withObservationTracking {
            settings.preferences
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeSettings() }
        }
        if preferences != reducer.state.preferences { send(.preferences(preferences)) }
    }

    private func send(_ event: BatteryReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .banner(let banner):
                context.activities.show(Self.banner(banner, level: model.snapshot?.level))
            case .wake(let date):
                wakeTimer.schedule(at: date)
            case .post(let snapshot):
                model.snapshot = snapshot
                context.activities.post(BatteryPresentation.activity(model: model, snapshot: snapshot))
            case .end:
                context.activities.end(Self.activityID, dismissal: .immediate)
            }
        }
    }

    // MARK: Banners

    static func banner(_ banner: BatteryReducer.Banner, level latest: Int?) -> TransientBanner {
        let id = Self.descriptor.id
        switch banner {
        case .charging(let level):
            return .standard(id: "battery.power", moduleID: id, content: BannerContent(
                label: "Charging", value: "\(level)%", accessory: .battery(level: level, isCharging: true, tint: .green)
            ), accessibilityLabel: "Charging, \(level) percent")
        case .pluggedIn(let level):
            return .standard(id: "battery.power", moduleID: id, content: BannerContent(
                label: "Plugged In", value: "\(level)%", accessory: .battery(level: level, isCharging: false, isPluggedIn: true, tint: .white)
            ), accessibilityLabel: "Plugged in, not charging, \(level) percent")
        case .charged:
            let level = latest ?? 100
            return .standard(id: "battery.power", moduleID: id, content: BannerContent(
                label: "Charged", value: "\(level)%", accessory: .battery(level: level, isCharging: false, tint: .green)
            ), accessibilityLabel: "Fully charged, \(level) percent")
        case .onBattery(let level):
            return .standard(id: "battery.power", moduleID: id, content: BannerContent(
                label: "On Battery", value: "\(level)%",
                accessory: .battery(level: level, isCharging: false, tint: BatteryPresentation.tint(level: level, charging: false))
            ), accessibilityLabel: "On battery, \(level) percent")
        case .low(let level):
            return .standard(id: "battery.low", moduleID: id, content: BannerContent(
                label: "Low Battery", labelTint: .red, value: "\(level)%", valueTint: .red,
                accessory: .battery(level: level, isCharging: false, tint: .red)
            ), priority: .high, accessibilityLabel: "Low battery, \(level) percent")
        }
    }
}

/// What the charging activity's views read.
@MainActor
@Observable
final class BatteryModel {
    var snapshot: PowerSnapshot?
}

/// The opt-in charging activity's regions (#26): a `.passive` activity, so
/// it sits beside whatever plays (ADR-0011).
@MainActor
enum BatteryPresentation {
    static func activity(model: BatteryModel, snapshot: PowerSnapshot) -> LiveActivity {
        LiveActivity(
            id: BatteryModule.activityID,
            moduleID: BatteryModule.descriptor.id,
            kind: .passive,
            title: "Charging",
            keylineTint: .green,
            accessibilityLabel: "Charging, \(snapshot.level) percent",
            staleNote: nil,
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { BatteryCompactGlyph(model: model) },
                compactTrailing: IslandRegion { BatteryPercent(model: model, font: IslandFont.compact) },
                minimal: IslandRegion { BatteryRing(model: model, size: 20, lineWidth: 2.5, showsBolt: true) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        BatteryRing(model: model, size: 52, lineWidth: 4.5, showsPercent: true)
                            .padding(.top, 6)
                    },
                    center: ExpandedRegion { BatteryExpandedText(model: model) }
                )
            )
        )
    }

    /// Green while charging, red at 10 % or less on battery, white otherwise.
    static func tint(level: Int, charging: Bool) -> Color {
        if charging { return .green }
        return level <= 10 ? .red : .white
    }
}

private struct BatteryCompactGlyph: View {
    let model: BatteryModel

    var body: some View {
        let level = model.snapshot?.level ?? 0
        BatteryGlyph(level: level, isCharging: true, tint: .green, width: 22, height: 11)
    }
}

private struct BatteryPercent: View {
    let model: BatteryModel
    let font: Font

    var body: some View {
        Text("\(model.snapshot?.level ?? 0)%")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

/// The level as a ring, like the iPhone's Batteries widget.
private struct BatteryRing: View {
    let model: BatteryModel
    let size: CGFloat
    let lineWidth: CGFloat
    var showsPercent = false
    var showsBolt = false

    var body: some View {
        let level = model.snapshot?.level ?? 0
        ZStack {
            Circle().stroke(.green.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(.green, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsPercent {
                Text("\(level)%")
                    .font(.system(size: size * 0.27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else if showsBolt {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: level)
    }
}

private struct BatteryExpandedText: View {
    let model: BatteryModel

    var body: some View {
        let snapshot = model.snapshot
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Charging")
                .font(IslandFont.title)
            if let minutes = snapshot?.minutesToFull {
                Text("Full in \(Duration.seconds(minutes * 60), format: .units(allowed: [.hours, .minutes], width: .abbreviated))")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot?.adapterWatts.map { "Power Adapter · \($0) W" } ?? "Power Adapter")
                .font(IslandFont.subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
