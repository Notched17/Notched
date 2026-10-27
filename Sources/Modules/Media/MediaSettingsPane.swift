// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Modules ▸ Now Playing.
struct MediaSettingsPane: View {
    @Bindable var settings: MediaSettings
    let registry: ModuleRegistry

    private var module: MediaModule? {
        registry.runningIDs.contains(MediaModule.descriptor.id) ? registry.module(MediaModule.descriptor.id) as? MediaModule : nil
    }

    var body: some View {
        Form {
            Section {
                Picker("Read from", selection: $settings.backend) {
                    ForEach(BackendPreference.allCases) { Text($0.title).tag($0) }
                }
                MediaSourceStatus(service: module?.service)
            } header: {
                Text("Source")
            } footer: {
                Text("Automatic follows whatever shows in Control Center's Now Playing, in any app. If that stops working on a future macOS, Notched falls back to Music and Spotify, which asks once for permission to control them.")
            }

            Section("Island") {
                Picker("Visualiser", selection: $settings.visualizer) {
                    ForEach(VisualizerStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Briefly expand when the track changes", isOn: $settings.expandOnTrackChange)
                Picker("Dim after pausing for", selection: $settings.staleAfterMinutes) {
                    ForEach(MediaSettings.staleAfterChoices, id: \.self) { Text(Self.minutes($0)).tag($0) }
                }
                Picker("Hide after pausing for", selection: $settings.endAfterMinutes) {
                    ForEach(MediaSettings.endAfterChoices, id: \.self) { Text(Self.minutes($0)).tag($0) }
                }
            }

            Section {
                Toggle("Show synced lyrics", isOn: $settings.lyricsEnabled)
                Toggle("Show the current line beside the notch", isOn: $settings.lyricsTicker)
                    .disabled(!settings.lyricsEnabled)
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Lyrics come from LRCLIB, a free community database. Only while lyrics are on, Notched sends it the title, artist, album and length of what's playing, and keeps the lyrics it finds on this Mac.")
            }

            Section {
                ForEach(settings.ignoredApps.sorted(), id: \.self) { bundleID in
                    IgnoredAppRow(bundleID: bundleID) { settings.ignoredApps.remove(bundleID) }
                }
                Menu("Add App…") {
                    ForEach(Self.candidateApps(excluding: settings.ignoredApps), id: \.bundleID) { app in
                        Button(app.name) { settings.ignoredApps.insert(app.bundleID) }
                    }
                    Divider()
                    Button("Choose…") { chooseApp() }
                }
                .fixedSize()
            } header: {
                Text("Ignored Apps")
            } footer: {
                Text("Media from these apps never appears on the island.")
            }

            Section {
                LabeledContent("Media keys") {
                    Text("Arrives with HUD replacement")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Choosing which player the play/pause key controls comes in a later version.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Now Playing")
    }

    private static func minutes(_ value: Int) -> String {
        value == 1 ? "1 minute" : "\(value) minutes"
    }

    /// Running apps with a Dock icon, as likely media sources.
    private static func candidateApps(excluding ignored: Set<String>) -> [(bundleID: String, name: String)] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own, !ignored.contains(id) else { return nil }
            return (id, app.localizedName ?? id)
        }
        return Dictionary(apps, uniquingKeysWith: { first, _ in first })
            .map { (bundleID: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        settings.ignoredApps.insert(id)
    }
}

/// Which backend is reading media, or why none can, with a way to fix it.
private struct MediaSourceStatus: View {
    let service: NowPlayingService?

    var body: some View {
        LabeledContent("Status") {
            HStack(spacing: Spacing.s) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(text).foregroundStyle(.secondary)
                if let service, service.isCheckingAdapter {
                    ProgressView().controlSize(.small)
                }
            }
        }
        if let service {
            if case .unavailable(let reason) = service.selection, reason == .automationDenied || reason == .noScriptablePlayers {
                Button("Open Automation Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if case .failed = service.adapterHealth {
                Button("Check Again") { Task { await service.checkAdapterAgain() } }
                    .disabled(service.isCheckingAdapter)
            }
        }
    }

    private var text: String {
        guard let service else { return "Turn on Now Playing to see its status" }
        switch service.selection {
        case .active(.adapter):
            return service.adapterHealth == .healthy ? "Reading any app" : "Reading any app (waiting for something to play)"
        case .active(.scripting):
            if case .failed = service.adapterHealth { return "Music and Spotify only: reading other apps stopped working" }
            return "Reading Music and Spotify"
        case .unavailable(.adapterFailed):
            return "Reading other apps doesn't work on this Mac"
        case .unavailable(.adapterFailedAndNoFallback):
            return "Not working: reading apps failed, and Music and Spotify aren't available"
        case .unavailable(.noScriptablePlayers):
            return "Music and Spotify aren't installed"
        case .unavailable(.automationDenied):
            return "Notched isn't allowed to control Music or Spotify"
        }
    }

    private var color: Color {
        guard let service else { return .secondary }
        switch service.selection {
        case .active(.adapter): return service.adapterHealth == .healthy ? .green : .yellow
        case .active(.scripting): return .yellow
        case .unavailable: return .red
        }
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: Spacing.s) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
            Spacer()
            Button("Remove", systemImage: "minus.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop ignoring this app")
        }
    }
}
