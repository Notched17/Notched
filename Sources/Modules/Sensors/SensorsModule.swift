// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// Camera & Microphone (#31): an orange dot while an app is using the
/// microphone and a green one for the camera, like iPhone. A thin shell around
/// `SensorIndicatorReducer`; the system work is the shared `SensorUsageService`,
/// which only listens while this module (or Calls) holds it.
///
/// Needs no permission: it reads whether a device is running, never what it
/// records.
@MainActor
final class SensorsModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "sensors",
        name: "Camera & Microphone",
        symbol: "mic.fill",
        summary: "An orange dot when an app is using your microphone and a green one for the camera, like iPhone.",
        permissions: [],
        isDebugOnly: false,
        isOnByDefault: true
    )
    static let activityID: ActivityID = "sensors"

    static func settingsPane(_ context: ModuleSettingsContext) -> AnyView? {
        AnyView(SensorsSettingsPane(settings: context.settings.sensors))
    }

    private let context: ModuleContext
    private let deadline = OneShotTimer()
    private let observers = NotificationTokens()
    private var reducer = SensorIndicatorReducer()
    private(set) var isRunning = false
    private var lastSerial = 0
    private var lastClaims: CallClaims?
    private var lastPreferences: SensorIndicatorReducer.Preferences?

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reducer = SensorIndicatorReducer()
        lastSerial = 0
        lastClaims = nil
        lastPreferences = nil
        deadline.action = { [weak self] in self?.send(.tick) }
        let sensors = context.services.sensors
        observers.observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter) { [weak self] in
            self?.send(.wake)
            self?.context.services.sensors.refresh()
        }
        sensors.acquire()
        observe()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers.invalidate()
        deadline.schedule(at: nil)
        context.services.sensors.release()
        context.activities.endAll()
    }

    #if DEBUG
    /// A simulated reading, as if the system had reported it.
    func simulate(_ reading: SensorSnapshot) { context.services.sensors.simulate(reading) }

    /// Simulated Calls claims.
    func simulate(claims: CallClaims) { context.services.sensors.setCallClaims(claims) }
    #endif

    /// Passes on whatever changed: a new reading, the Calls module's claims, or a setting.
    private func observe() {
        guard isRunning else { return }
        let sensors = context.services.sensors
        let settings = context.settings.sensors
        // Only the reads are tracked; what they cause is handled after.
        let (serial, claims, preferences, snapshot) = withObservationTracking {
            (sensors.readingSerial, sensors.callClaims, settings.preferences, sensors.snapshot)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        if preferences != lastPreferences {
            lastPreferences = preferences
            send(.preferences(preferences))
        }
        if claims != lastClaims {
            lastClaims = claims
            send(.claims(claims))
        }
        // A fresh reading, even an unchanged one (after wake), but not the
        // placeholder before the monitor has read anything.
        if serial != lastSerial {
            lastSerial = serial
            if serial > 0 { send(.snapshot(snapshot)) }
        }
    }

    private func send(_ event: SensorIndicatorReducer.Event) {
        guard isRunning else { return }
        for effect in reducer.reduce(event, now: Date()) {
            switch effect {
            case .post(let model):
                context.activities.post(SensorsPresentation.activity(model: model))
            case .end:
                context.activities.end(Self.activityID, dismissal: .immediate)
            case .schedule(let date):
                deadline.schedule(at: date)
            }
        }
    }
}

/// Camera & Microphone's regions (#31): `.live`, and not hideable while the
/// camera is on (a privacy indicator).
@MainActor
enum SensorsPresentation {
    static let micTint = Color.orange
    static let cameraTint = Color.green

    static func activity(model: SensorIndicatorReducer.Model) -> LiveActivity {
        LiveActivity(
            id: SensorsModule.activityID,
            moduleID: SensorsModule.descriptor.id,
            kind: .live,
            title: "Camera & Microphone",
            // Above the user's own timers: a privacy indicator.
            relevance: 100,
            isHideable: !model.camera,
            keylineTint: model.camera ? cameraTint : micTint,
            accessibilityLabel: SensorText.accessibilityLabel(model),
            staleNote: nil,
            presentation: ActivityPresentation(
                compactLeading: IslandRegion { SensorGlyphs(model: model) },
                compactTrailing: IslandRegion { SensorDots(model: model, size: 9) },
                minimal: IslandRegion { SensorDots(model: model, size: 9) },
                expanded: ExpandedPresentation(
                    leading: ExpandedRegion {
                        IslandTile { SensorGlyphs(model: model, size: 18) }
                            .padding(.top, 6)
                    },
                    bottom: ExpandedRegion {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text(SensorText.title(model)).font(IslandFont.title)
                            if model.mic { SensorRow(tint: micTint, label: "Microphone", detail: SensorText.micDetail(model)) }
                            if model.camera { SensorRow(tint: cameraTint, label: "Camera", detail: SensorText.cameraDetail) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                )
            )
        )
    }
}

/// The camera and microphone glyphs, each in its colour.
private struct SensorGlyphs: View {
    let model: SensorIndicatorReducer.Model
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if model.camera {
                Image(systemName: "video.fill").foregroundStyle(SensorsPresentation.cameraTint)
            }
            if model.mic {
                Image(systemName: "mic.fill").foregroundStyle(SensorsPresentation.micTint)
            }
        }
        .font(.system(size: size, weight: .semibold))
    }
}

/// The dots: orange for the microphone, green for the camera.
private struct SensorDots: View {
    let model: SensorIndicatorReducer.Model
    let size: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            if model.mic { Circle().fill(SensorsPresentation.micTint).frame(width: size, height: size) }
            if model.camera { Circle().fill(SensorsPresentation.cameraTint).frame(width: size, height: size) }
        }
    }
}

private struct SensorRow: View {
    let tint: Color
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(label).font(IslandFont.subtitle.weight(.semibold))
            Text(detail).font(IslandFont.subtitle).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}
