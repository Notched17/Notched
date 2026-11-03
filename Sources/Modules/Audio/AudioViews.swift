// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

/// What the App Volume tab shows and can do (#17).
@MainActor
@Observable
final class MixerModel {
    /// The apps to list: playing now, or still turned down.
    var apps: [MixerReducer.App] = []
    let outputs: AudioOutputService
    @ObservationIgnored var send: (MixerReducer.Event) -> Void = { _ in }
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(outputs: AudioOutputService) {
        self.outputs = outputs
    }

    /// Playing apps first, then by name.
    var sortedApps: [MixerReducer.App] {
        apps.sorted {
            $0.isPlaying != $1.isPlaying ? $0.isPlaying : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var anyTurnedDown: Bool { apps.contains { $0.gain < 1 } }

    func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    func setVolume(_ app: MixerReducer.App, _ value: Double) { send(.setVolume(app.id, value)) }
    func toggleMute(_ app: MixerReducer.App) { send(.setMuted(app.id, !app.isMuted)) }
    func retry(_ app: MixerReducer.App) { send(.retry(app.id)) }
}

/// The App Volume tab: the output on top, then a slider per app.
struct AudioMixerTabView: View {
    let model: MixerModel

    var body: some View {
        VStack(spacing: Spacing.s) {
            OutputRow(outputs: model.outputs)
            let rows = model.sortedApps
            if rows.isEmpty {
                Text("Nothing is playing. Apps that play sound will show up here.")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(rows) { app in
                            AppVolumeRow(app: app, model: model)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 112)
            }
            if model.anyTurnedDown {
                Text("macOS shows a purple dot while an app is turned down. Nothing is recorded.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The current output, with a menu to switch (the M2 switcher).
private struct OutputRow: View {
    let outputs: AudioOutputService

    var body: some View {
        HStack(spacing: Spacing.s) {
            Menu {
                ForEach(outputs.devices) { device in
                    Button {
                        outputs.select(device)
                    } label: {
                        Label(device.name, systemImage: device.id == outputs.current?.id ? "checkmark" : device.symbol)
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: outputs.current?.symbol ?? "speaker.wave.2")
                    Text(outputs.current?.name ?? "No output")
                        .lineLimit(1)
                }
                .font(IslandFont.subtitle)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Output")
            .accessibilityValue(outputs.current?.name ?? "None")
            Spacer(minLength: 0)
        }
    }
}

private struct AppVolumeRow: View {
    let app: MixerReducer.App
    let model: MixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.s) {
                Group {
                    if let icon = model.icon(for: app.id) {
                        Image(nsImage: icon).resizable().scaledToFit()
                    } else {
                        Image(systemName: "app").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 78, alignment: .leading)

                Slider(value: Binding(get: { app.isMuted ? 0 : app.volume }, set: { model.setVolume(app, $0) }), in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("\(app.name) volume")
                    .accessibilityValue("\(Int((app.isMuted ? 0 : app.volume) * 100)) percent")

                Text("\(Int((app.isMuted ? 0 : app.volume) * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)

                Button {
                    model.toggleMute(app)
                } label: {
                    Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.isMuted ? .primary : .secondary)
                .accessibilityLabel(app.isMuted ? "Unmute \(app.name)" : "Mute \(app.name)")
            }
            if let problem = app.problem {
                HStack(spacing: Spacing.s) {
                    Text(Self.message(problem, name: app.name))
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if problem == .silent {
                        Button("Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!)
                        }
                    }
                    Button("Try Again") { model.retry(app) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
            }
        }
    }

    static func message(_ problem: MixerReducer.Problem, name: String) -> String {
        switch problem {
        case .silent: "Notched couldn't hear \(name). If audio access was turned off, allow it in System Settings."
        case .failed: "Can't control \(name)."
        }
    }
}
