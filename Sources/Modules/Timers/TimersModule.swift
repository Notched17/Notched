// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Timers and the stopwatch (#37), as `.live` activities. A thin shell
/// around `TimersReducer`: everything is a date, so there's no per-second
/// work; one `OneShotTimer` waits for the next end (it counts time asleep),
/// and waking re-checks. Timers are saved, so they survive a relaunch.
@MainActor
final class TimersModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "timers",
        name: "Timers",
        symbol: "timer",
        summary: "Countdown timers and a stopwatch beside the notch. Start one from the island, the menu bar or a notched://timer link.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: true
    )
    static let stopwatchID: ActivityID = "timers.stopwatch"
    static let presets: [Int] = [1, 5, 10, 25]

    static func activityID(_ id: UUID) -> ActivityID { ActivityID("timers.\(id.uuidString)") }

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(TimersSettingsPane(settings: context.settings.timers))
    }

    let model = TimersModel()
    private let context: ModuleContext
    private let settings: TimersSettings
    private var reducer = TimersReducer()
    private let deadline = OneShotTimer()
    private let observers = NotificationTokens()
    private var isRunning = false
    /// The relevance each timer was last posted with, so a change re-ranks it.
    private var postedRelevance: [UUID: Double] = [:]

    init(context: ModuleContext) {
        self.context = context
        settings = context.settings.timers
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reducer = TimersReducer(doneHold: context.settings.alertDuration)
        model.actions = TimersActions(
            start: { [weak self] seconds, label in self?.startTimer(seconds: seconds, label: label) },
            pause: { [weak self] id in self?.send(.pause(id)) },
            resume: { [weak self] id in self?.send(.resume(id)) },
            addMinute: { [weak self] id in self?.send(.addMinute(id)) },
            cancel: { [weak self] id in self?.send(.cancel(id)) },
            stopwatchStart: { [weak self] in self?.send(.stopwatchStart) },
            stopwatchPause: { [weak self] in self?.send(.stopwatchPause) },
            stopwatchReset: { [weak self] in self?.send(.stopwatchReset) }
        )
        deadline.action = { [weak self] in self?.send(.deadline) }
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.send(.wake)
        }
        if let saved = settings.savedState { send(.restore(saved)) }
        publishHomeAction()
    }

    /// Stopping (turning the module off, or quitting) keeps the saved timers:
    /// they carry on when the module next starts.
    func stop() {
        isRunning = false
        observers.invalidate()
        deadline.schedule(at: nil)
        model.actions = TimersActions()
        postedRelevance.removeAll()
        context.activities.endAll()
    }

    /// Starts a countdown: from the island, the status menu or a URL.
    func startTimer(seconds: TimeInterval, label: String? = nil) {
        send(.start(duration: seconds, label: label, id: UUID()))
    }

    func start(_ request: TimerRequest) {
        startTimer(seconds: request.duration, label: request.label)
    }

    private func send(_ event: TimersReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .post(let item):
                post(item, alert: nil)
            case .alert(let item, let sound):
                // The module plays the sound, so it rings even with alert expansion off.
                if sound { playSound() }
                post(item, alert: AlertRequest(duration: .milliseconds(Int(reducer.doneHold * 1000))))
            case .end(let id, let toRecent):
                postedRelevance[id] = nil
                context.activities.end(Self.activityID(id), dismissal: toRecent ? .default : .immediate)
            case .postStopwatch(let stopwatch):
                context.activities.post(TimersPresentation.stopwatch(stopwatch, model: model))
            case .endStopwatch:
                context.activities.end(Self.stopwatchID, dismissal: .immediate)
            case .schedule(let date):
                deadline.schedule(at: date)
            case .persist(let state):
                settings.save(state)
            }
        }
        model.state = reducer.state
        rerank()
        publishHomeAction()
    }

    private func post(_ item: TimerItem, alert: AlertRequest?) {
        let relevance = reducer.state.relevance(of: item.id)
        postedRelevance[item.id] = relevance
        context.activities.post(TimersPresentation.timer(item, relevance: relevance, model: model), alert: alert)
    }

    /// The soonest-ending timer ranks first; another timer starting or ending can change that.
    private func rerank() {
        for item in reducer.state.timers {
            guard let posted = postedRelevance[item.id], posted != reducer.state.relevance(of: item.id) else { continue }
            post(item, alert: nil)
        }
    }

    private func playSound() {
        guard !settings.sound.isEmpty else { return }
        NSSound(named: NSSound.Name(settings.sound))?.play()
    }

    private func publishHomeAction() {
        guard isRunning else { return }
        let model = model
        let running = model.state.timers.filter { if case .done = $0.phase { false } else { true } }.count
        context.activities.setHomeActions([HomeAction(
            id: "timers",
            moduleID: Self.descriptor.id,
            title: "Timer",
            symbol: "timer",
            isOn: running > 0 || model.state.stopwatch != nil,
            tint: TimersPresentation.tint,
            accessibilityValue: running > 0 ? "\(running) running" : nil,
            panel: IslandRegion { TimerComposer(model: model, closesPanel: true, offersStopwatch: true) }
        )])
    }

    // MARK: Status menu

    func menuItems() -> [NSMenuItem] {
        let item = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false
        for minutes in Self.presets {
            menu.addItem(ClosureMenuItem(title: minutes == 1 ? "1 Minute" : "\(minutes) Minutes") { [weak self] in
                self?.startTimer(seconds: TimeInterval(minutes * 60))
            })
        }
        menu.addItem(.separator())
        if let stopwatch = model.state.stopwatch {
            menu.addItem(ClosureMenuItem(title: stopwatch.isRunning ? "Pause Stopwatch" : "Resume Stopwatch") { [weak self] in
                self?.send(stopwatch.isRunning ? .stopwatchPause : .stopwatchStart)
            })
            menu.addItem(ClosureMenuItem(title: "Reset Stopwatch") { [weak self] in self?.send(.stopwatchReset) })
        } else {
            menu.addItem(ClosureMenuItem(title: "Start Stopwatch") { [weak self] in self?.send(.stopwatchStart) })
        }
        let active = model.state.timers.filter { if case .done = $0.phase { false } else { true } }
        if !active.isEmpty {
            menu.addItem(.separator())
            for timer in active {
                let left = TimersPresentation.remainingText(timer.remaining(at: Date()))
                menu.addItem(ClosureMenuItem(title: "Cancel \(timer.label) (\(left) left)") { [weak self] in
                    self?.send(.cancel(timer.id))
                })
            }
        }
        item.submenu = menu
        item.state = active.isEmpty ? .off : .on
        return [item]
    }
}

/// What the timer views can do.
@MainActor
struct TimersActions {
    var start: (TimeInterval, String?) -> Void = { _, _ in }
    var pause: (UUID) -> Void = { _ in }
    var resume: (UUID) -> Void = { _ in }
    var addMinute: (UUID) -> Void = { _ in }
    var cancel: (UUID) -> Void = { _ in }
    var stopwatchStart: () -> Void = {}
    var stopwatchPause: () -> Void = {}
    var stopwatchReset: () -> Void = {}
}

@MainActor
@Observable
final class TimersModel {
    var state = TimersState()
    /// The custom stepper's minutes, kept while the island stays open.
    var customMinutes = 15
    @ObservationIgnored var actions = TimersActions()

    func item(_ id: UUID) -> TimerItem? { state.timers.first { $0.id == id } }
}

/// Settings ▸ Modules ▸ Timers.
struct TimersSettingsPane: View {
    @Bindable var settings: TimersSettings

    var body: some View {
        Form {
            Section {
                Picker("Sound", selection: $settings.sound) {
                    Text("None").tag("")
                    Divider()
                    ForEach(TimersSettings.availableSounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: settings.sound) { _, sound in
                    if !sound.isEmpty { NSSound(named: NSSound.Name(sound))?.play() }
                }
            } footer: {
                Text("When a timer ends, the island expands for a moment and the sound plays. The sound plays even if you've turned off expanding for alerts.")
            }
            Section {
                LabeledContent("From any app or shortcut") {
                    Text("notched://timer?minutes=10&label=Tea")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            } footer: {
                Text("Opening this link starts a timer. Use minutes, seconds or hours (they add up), and an optional label.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Timers")
    }
}
