// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// App Volume (#17, ADR-0029): a slider per app that is playing, in a tab of
/// the expanded island. A thin shell around the pure `MixerReducer`: the
/// process monitor reports apps, the engine builds Core Audio taps, and
/// nothing is tapped until a slider is moved below 100 %.
@MainActor
final class AudioModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "audio",
        name: "App Volume",
        symbol: "slider.horizontal.3",
        summary: "A volume slider for each app that is playing. Needs audio recording permission, asked when you first move a slider.",
        permissions: [.audioCapture],
        isDebugOnly: false,
        isOnByDefault: false
    )

    static let tabID = "audio.mixer"

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(AudioSettingsPane(permissions: context.permissions))
    }

    private let context: ModuleContext
    private let outputs: AudioOutputService
    private let monitor = AudioAppMonitor()
    private let engine = ProcessTapEngine()
    private let wakeTimer = OneShotTimer()
    private var reducer = MixerReducer()
    private var nextWake: Date?
    private var lastOutputID: UInt32?
    private var isRunning = false
    private var holdsOutputs = false
    let model: MixerModel

    init(context: ModuleContext) {
        self.context = context
        outputs = context.services.audioOutputs
        model = MixerModel(outputs: outputs)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        model.send = { [weak self] event in self?.send(event) }
        wakeTimer.action = { [weak self] in self?.judgeProbation() }
        engine.onStarted = { [weak self] app in self?.send(.tapStarted(app)) }
        engine.onFailed = { [weak self] app in self?.send(.tapFailed(app)) }
        monitor.onChange = { [weak self] apps in self?.send(.apps(apps)) }
        outputs.acquire()
        holdsOutputs = true
        lastOutputID = outputs.current?.id
        observeOutput()
        monitor.start()
        publishTab()
    }

    func stop() {
        isRunning = false
        // Taps end with their engine: every app is back at full volume.
        engine.stopAll()
        engine.onStarted = nil
        engine.onFailed = nil
        monitor.stop()
        wakeTimer.schedule(at: nil)
        nextWake = nil
        if holdsOutputs {
            holdsOutputs = false
            outputs.release()
        }
        reducer = MixerReducer()
        model.apps = []
        model.send = { _ in }
        context.activities.setTabs([])
    }

    // MARK: Events and effects

    private func send(_ event: MixerReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .startTap(let app, let gain): engine.start(app: app, gain: gain)
            case .setGain(let app, let gain): engine.setGain(app: app, gain)
            case .stopTap(let app): engine.stop(app: app)
            case .rebuildTap(let app): engine.rebuild(app: app)
            case .wake(let date): scheduleWake(date)
            case .recordPermission(let granted):
                AudioCaptureAccess.record(granted ? .granted : .denied)
            }
        }
        model.apps = reducer.apps.filter(\.isListed)
    }

    /// Keeps the earliest of the requested wakes.
    private func scheduleWake(_ date: Date) {
        if let nextWake, nextWake > Date(), nextWake <= date { return }
        nextWake = date
        wakeTimer.schedule(at: date)
    }

    /// The probation deadline: tell the reducer which taps have delivered
    /// sound, then let it judge the rest.
    private func judgeProbation() {
        nextWake = nil
        for app in reducer.onProbation where engine.hasHeardSound(app: app) { send(.heard(app)) }
        send(.tick)
    }

    private func observeOutput() {
        guard isRunning else { return }
        let id = withObservationTracking {
            outputs.current?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeOutput() }
        }
        guard id != lastOutputID else { return }
        lastOutputID = id
        send(.outputChanged)
    }

    private func publishTab() {
        let model = model
        context.activities.setTabs([IslandTab(
            id: Self.tabID, moduleID: Self.descriptor.id, title: "Volume", symbol: "slider.horizontal.3",
            accessibilityLabel: "App volume", order: 40
        ) { AudioMixerTabView(model: model) }])
    }

    // MARK: Status menu

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: "Reset App Volumes") { [weak self] in self?.send(.resetAll) }]
    }
}

/// Settings ▸ Modules ▸ App Volume.
struct AudioSettingsPane: View {
    let permissions: PermissionCenter?

    var body: some View {
        Form {
            Section {
                if let permissions {
                    LabeledContent("System audio recording", value: Self.describe(permissions.status(.audioCapture)))
                    if permissions.status(.audioCapture) == .denied {
                        Button("Open System Settings") { permissions.openSystemSettings(for: .audioCapture) }
                    }
                }
            } footer: {
                Text("Notched turns an app down by briefly capturing its sound and playing it back quieter. macOS asks for permission the first time you move a slider, and shows a purple recording dot while an app is turned down. Nothing is recorded, saved or sent anywhere, and every app returns to full volume when you set its slider back to 100 %, reset the volumes from the menu bar, or quit Notched.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("App Volume")
    }

    private static func describe(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: "Allowed"
        case .denied: "Not allowed (as far as Notched could tell)"
        default: "Asked when you first move a slider"
        }
    }
}
