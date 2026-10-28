// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Calls: "In a call" with a running duration, for the known call apps. A thin
/// shell around `CallReducer` over the shared `SensorUsageService`. Needs no
/// permission: it reads which apps use the microphone, never what they hear.
///
/// A `.system` activity that can't be hidden (ISLAND-BEHAVIOR.md §2). It also
/// tells Camera & Microphone which apps are in a call, so a call is one island
/// item and not a call plus a microphone dot. Those claims are cleared when
/// this module stops, so a stopped or suspended Calls module can never hide the
/// microphone indicator.
///
/// There is no Mute or End button: none of these apps has a public way to do
/// that from outside, and a button that only looks like it works is worse than
/// none. A click opens the call app.
@MainActor
final class CallsModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "calls",
        name: "Calls",
        symbol: "phone.fill",
        summary: "Shows when you're in a call in FaceTime, Zoom, Teams, Slack, Discord or Webex, and for how long. It can't see who's calling.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: false
    )

    static func activityID(_ appID: String) -> ActivityID { ActivityID("calls.\(appID)") }

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(CallsSettingsPane(settings: context.settings.calls))
    }

    private let context: ModuleContext
    private let deadline = OneShotTimer()
    private let observers = NotificationTokens()
    private var terminationToken: (any NSObjectProtocol)?
    private var reducer = CallReducer()
    private(set) var isRunning = false
    private var lastSerial = 0
    private var lastApps: Set<CallReducer.App>?
    private var lastCamera: Bool?

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reducer = CallReducer()
        lastSerial = 0
        lastApps = nil
        lastCamera = nil
        deadline.action = { [weak self] in self?.send(.tick) }
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.send(.wake)
            self?.context.services.sensors.refresh()
        }
        terminationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.send(.appQuit(id)) }
        }
        context.services.sensors.acquire()
        observe()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers.invalidate()
        if let terminationToken { NSWorkspace.shared.notificationCenter.removeObserver(terminationToken) }
        terminationToken = nil
        deadline.schedule(at: nil)
        // Clear first: Camera & Microphone may keep the service alive.
        context.services.sensors.setCallClaims(CallClaims())
        context.services.sensors.release()
        context.activities.endAll()
    }

    #if DEBUG
    /// A simulated reading, as if the system had reported it.
    func simulate(_ reading: SensorSnapshot) { context.services.sensors.simulate(reading) }
    #endif

    /// Passes on a new reading, or a change to which browsers count.
    private func observe() {
        guard isRunning else { return }
        let sensors = context.services.sensors
        let settings = context.settings.calls
        // Only the reads are tracked; what they cause is handled after.
        let (serial, snapshot, browsers) = withObservationTracking {
            (sensors.readingSerial, sensors.snapshot, settings.browsers)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        guard serial > 0 else { return }
        let apps = CallApps.apps(from: snapshot.micUsers, browsers: browsers)
        if snapshot.cameraRunning != lastCamera {
            lastCamera = snapshot.cameraRunning
            send(.camera(snapshot.cameraRunning))
        }
        // A fresh reading, even an unchanged one (after wake), or different apps.
        if serial != lastSerial || apps != lastApps {
            lastSerial = serial
            lastApps = apps
            send(.micUsers(apps))
        }
    }

    private func send(_ event: CallReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .post(let model):
                let appID = model.app.id
                context.activities.post(CallsPresentation.activity(model: model, open: { Self.open(appID) }))
            case .end(let appID):
                context.activities.end(Self.activityID(appID), dismissal: .immediate)
            case .claims(let claims):
                context.services.sensors.setCallClaims(claims)
            case .schedule(let date):
                deadline.schedule(at: date)
            }
        }
    }

    /// A click on the call opens the app it's in.
    private static func open(_ appID: String) {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == appID }?.activate()
    }
}

/// A call's regions: `.system`, so it ranks first (ISLAND-BEHAVIOR.md §2), and
/// not hideable. The duration is `Text(_, style: .timer)`, which the system
/// ticks: nothing here runs a timer of its own.
@MainActor
enum CallsPresentation {
    static let tint = Color.green
    static let micTint = Color.orange
    static let cameraTint = Color.green

    static func activity(model: CallReducer.Model, open: @escaping @MainActor () -> Void) -> LiveActivity {
        LiveActivity(
            id: CallsModule.activityID(model.app.id),
            moduleID: CallsModule.descriptor.id,
            kind: .system,
            title: "\(model.app.name) Call",
            isHideable: false,
            keylineTint: tint,
            accessibilityLabel: accessibilityLabel(model),
            openAction: open,
            staleNote: nil,
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { CallGlyph(model: model, size: 14) },
                compactTrailing: IslandRegion { CallDuration(startedAt: model.startedAt, font: IslandFont.compact) },
                minimal: IslandRegion {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        IslandTile { Image(systemName: "phone.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(tint) }
                            .padding(.top, 6)
                    },
                    trailing: ExpandedRegion { CallDuration(startedAt: model.startedAt, font: IslandFont.hero) },
                    bottom: ExpandedRegion {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("In a Call").font(IslandFont.title)
                                Text(model.app.name).font(IslandFont.subtitle).foregroundStyle(.secondary)
                            }
                            HStack(spacing: Spacing.m) {
                                CallIndicator(tint: micTint, label: "Microphone")
                                if model.camera { CallIndicator(tint: cameraTint, label: "Camera") }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
            )
        )
    }

    static func accessibilityLabel(_ model: CallReducer.Model) -> String {
        var label = "In a call in \(model.app.name)"
        if let startedAt = model.startedAt {
            label += ", started \(startedAt.formatted(.relative(presentation: .named)))"
        }
        return label + (model.camera ? ", camera on" : "")
    }
}

/// The phone glyph with the microphone dot, and the camera dot while it runs.
private struct CallGlyph: View {
    let model: CallReducer.Model
    let size: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "phone.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(CallsPresentation.tint)
            HStack(spacing: 3) {
                Circle().fill(CallsPresentation.micTint).frame(width: 6, height: 6)
                if model.camera { Circle().fill(CallsPresentation.cameraTint).frame(width: 6, height: 6) }
            }
        }
    }
}

/// How long the call has lasted, or just "In a call" when it was already going.
private struct CallDuration: View {
    let startedAt: Date?
    let font: Font

    var body: some View {
        Group {
            if let startedAt {
                Text(startedAt, style: .timer)
                    .monospacedDigit()
            } else {
                Text("In a call")
            }
        }
        .font(font)
        .foregroundStyle(CallsPresentation.tint)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct CallIndicator: View {
    let tint: Color
    let label: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(label).font(IslandFont.subtitle).foregroundStyle(.secondary)
        }
    }
}
