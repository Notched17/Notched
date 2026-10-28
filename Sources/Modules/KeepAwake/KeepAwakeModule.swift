// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Keep Awake (#38): keeps the display awake for a while, from Home, the
/// status menu or its expanded view. A thin shell around `KeepAwakeReducer`,
/// which holds at most one power assertion and never restores itself after
/// a relaunch. Does nothing until used.
@MainActor
final class KeepAwakeModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "keepawake",
        name: "Keep Awake",
        symbol: "cup.and.saucer.fill",
        summary: "Keeps your Mac and its display awake for a while. Start it from the island or the menu bar; it does nothing until you do.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: true
    )
    static let activityID: ActivityID = "keepawake"
    static let assertionReason = "Notched Keep Awake"

    let model = KeepAwakeModel()
    private let context: ModuleContext
    private let assertion: any PowerAssertionClient
    private let deadline = OneShotTimer()
    private let observers = NotificationTokens()
    private var reducer = KeepAwakeReducer()
    private var isRunning = false
    private let log = Log.module("keepawake")

    convenience init(context: ModuleContext) {
        self.init(context: context, assertion: IOPMPowerAssertionClient())
    }

    init(context: ModuleContext, assertion: any PowerAssertionClient) {
        self.context = context
        self.assertion = assertion
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.actions = KeepAwakeActions(
            start: { [weak self] preset in self?.send(.start(preset)) },
            stop: { [weak self] in self?.send(.stop) }
        )
        deadline.action = { [weak self] in self?.send(.deadline) }
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.send(.wake)
        }
        publishHomeAction()
    }

    func stop() {
        send(.quit)
        isRunning = false
        observers.invalidate()
        deadline.schedule(at: nil)
        model.actions = KeepAwakeActions()
        context.activities.endAll()
    }

    /// Whether the power assertion is held (tests and `pmset -g assertions`).
    var holdsAssertion: Bool { assertion.isHeld }

    func turnOn(_ preset: KeepAwakePreset) { send(.start(preset)) }
    func turnOff() { send(.stop) }

    private func send(_ event: KeepAwakeReducer.Event) {
        guard isRunning else { return }
        var failed = false
        for effect in reducer.reduce(event, now: Date()) {
            // Refused: nothing after it (no activity flashing on) happens.
            if failed { break }
            switch effect {
            case .acquire:
                failed = !assertion.acquire(reason: Self.assertionReason)
            case .release:
                assertion.release()
            case .post(let until):
                model.isOn = true
                model.until = until
                context.activities.post(KeepAwakePresentation.activity(model: model))
            case .end:
                model.isOn = false
                model.until = nil
                context.activities.end(Self.activityID, dismissal: .immediate)
            case .schedule(let date):
                deadline.schedule(at: date)
            }
        }
        if failed {
            log.error("Keep Awake couldn't start")
            send(.acquireFailed)
            return
        }
        publishHomeAction()
    }

    private func publishHomeAction() {
        guard isRunning else { return }
        let model = model
        context.activities.setHomeActions([HomeAction(
            id: "keepawake",
            moduleID: Self.descriptor.id,
            title: "Keep Awake",
            symbol: model.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
            isOn: model.isOn,
            tint: KeepAwakePresentation.tint,
            accessibilityValue: KeepAwakePresentation.statusText(until: model.until, isOn: model.isOn),
            panel: IslandRegion { KeepAwakeChoices(model: model, closesPanel: true) }
        )])
    }

    // MARK: Status menu

    func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        item.state = model.isOn ? .on : .off
        let menu = NSMenu()
        menu.autoenablesItems = false
        if model.isOn {
            let status = NSMenuItem(title: KeepAwakePresentation.statusText(until: model.until, isOn: true), action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(.separator())
        }
        for preset in KeepAwakePreset.allCases {
            menu.addItem(ClosureMenuItem(title: preset.menuTitle) { [weak self] in self?.turnOn(preset) })
        }
        menu.addItem(.separator())
        let off = ClosureMenuItem(title: "Turn Off") { [weak self] in self?.turnOff() }
        off.isEnabled = model.isOn
        menu.addItem(off)
        item.submenu = menu
        return [item]
    }
}

extension KeepAwakePreset {
    var title: String {
        switch self {
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 hr"
        case .twoHours: "2 hr"
        case .indefinitely: "Indefinitely"
        }
    }

    var menuTitle: String {
        switch self {
        case .thirtyMinutes: "For 30 Minutes"
        case .oneHour: "For 1 Hour"
        case .twoHours: "For 2 Hours"
        case .indefinitely: "Indefinitely"
        }
    }
}

/// What Keep Awake's views can do.
@MainActor
struct KeepAwakeActions {
    var start: (KeepAwakePreset) -> Void = { _ in }
    var stop: () -> Void = {}
}

@MainActor
@Observable
final class KeepAwakeModel {
    var isOn = false
    /// Nil while on means until turned off.
    var until: Date?
    @ObservationIgnored var actions = KeepAwakeActions()
}

/// Keep Awake's regions (#38): `.live`, below whatever plays (ADR-0011).
@MainActor
enum KeepAwakePresentation {
    static let tint = Color.brown
    static let symbol = "cup.and.saucer.fill"

    static func activity(model: KeepAwakeModel) -> LiveActivity {
        LiveActivity(
            id: KeepAwakeModule.activityID,
            moduleID: KeepAwakeModule.descriptor.id,
            kind: .live,
            title: "Keep Awake",
            relevance: 10,
            keylineTint: tint,
            accessibilityLabel: "Keep Awake, \(statusText(until: model.until, isOn: true))",
            staleNote: nil,
            presentation: ActivityPresentation(
                compactLeading: IslandRegion {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                },
                compactTrailing: IslandRegion { KeepAwakeRemaining(model: model, font: IslandFont.compact) },
                minimal: IslandRegion { KeepAwakeMinimal(model: model) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        IslandTile {
                            Image(systemName: symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(tint)
                        }
                        .padding(.top, 6)
                    },
                    trailing: ExpandedRegion { KeepAwakeRemaining(model: model, font: IslandFont.hero) },
                    bottom: ExpandedRegion {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("Keeping Awake").font(IslandFont.title)
                                Text(statusText(until: model.until, isOn: true))
                                    .font(IslandFont.subtitle)
                                    .foregroundStyle(.secondary)
                            }
                            KeepAwakeChoices(model: model, closesPanel: false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
            )
        )
    }

    static func statusText(until: Date?, isOn: Bool) -> String {
        guard isOn else { return "Off" }
        guard let until else { return "Until you turn it off" }
        return "Until \(until.formatted(date: .omitted, time: .shortened))"
    }
}

/// The time left, or "On" with no end.
private struct KeepAwakeRemaining: View {
    let model: KeepAwakeModel
    let font: Font

    var body: some View {
        Group {
            if let until = model.until {
                Text(timerInterval: Date.now...max(until, .now), countsDown: true)
            } else {
                Text("On")
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(KeepAwakePresentation.tint)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
    }
}

/// The bubble: the countdown (shrunk to fit past an hour), or the cup.
private struct KeepAwakeMinimal: View {
    let model: KeepAwakeModel

    var body: some View {
        if let until = model.until {
            WidthCap(maxWidth: IslandMetrics.bubbleMaxWidth - 2 * IslandMetrics.bubblePadding) {
                Text(timerInterval: Date.now...max(until, .now), countsDown: true)
                    .font(IslandFont.minimal)
                    .monospacedDigit()
                    .foregroundStyle(KeepAwakePresentation.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else {
            Image(systemName: KeepAwakePresentation.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(KeepAwakePresentation.tint)
        }
    }
}

/// The presets, and Turn Off while on: on Home's panel and in the expanded view.
struct KeepAwakeChoices: View {
    let model: KeepAwakeModel
    let closesPanel: Bool
    @Environment(\.closeHomePanel) private var closePanel

    var body: some View {
        IslandChipRow {
            ForEach(KeepAwakePreset.allCases, id: \.self) { preset in
                Button(preset.title) {
                    model.actions.start(preset)
                    if closesPanel { closePanel() }
                }
                .buttonStyle(.island)
                .accessibilityLabel(preset == .indefinitely ? "Keep awake until turned off" : "Keep awake \(preset.menuTitle.lowercased())")
            }
            if model.isOn {
                Button("Turn Off", systemImage: "xmark") {
                    model.actions.stop()
                    if closesPanel { closePanel() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.island(prominent: KeepAwakePresentation.tint))
                .accessibilityLabel("Turn off Keep Awake")
            }
        }
    }
}
