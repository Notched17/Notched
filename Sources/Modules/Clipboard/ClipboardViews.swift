// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import KeyboardShortcuts
import SwiftUI

/// The Clipboard tab (#45): a search field over the list. Click a row to copy
/// it back; right-click for Pin and Delete.
struct ClipboardTabView: View {
    @Bindable var model: ClipboardModel

    var body: some View {
        VStack(spacing: Spacing.s) {
            SearchField(text: $model.query)
            let rows = model.visible
            if rows.isEmpty {
                Text(model.entries.isEmpty ? "Nothing copied yet. Copy something and it will show up here." : "No matches.")
                    .font(IslandFont.subtitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { entry in
                            ClipboardRow(entry: entry, model: model)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 96)
            }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 5)
        .background(.white.opacity(0.1), in: Capsule())
        .accessibilityElement(children: .contain)
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let model: ClipboardModel

    var body: some View {
        Button { model.actions.copy(entry.id) } label: {
            HStack(spacing: Spacing.s) {
                leading
                    .frame(width: 22, height: 22)
                Text(entry.preview)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                if let icon = model.icon(for: entry.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(entry.isPinned ? "Unpin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin") { model.actions.togglePin(entry.id) }
            Button("Delete", systemImage: "trash", role: .destructive) { model.actions.delete(entry.id) }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Copies it back to the clipboard")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var leading: some View {
        if let thumbnail = model.thumbnail(for: entry) {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        let kind: String = switch entry.kind {
        case .text: "Text"
        case .url: "Link"
        case .file: "File"
        case .image: "Image"
        }
        let pinned = entry.isPinned ? ", pinned" : ""
        return "\(kind)\(pinned): \(entry.preview)"
    }
}

// MARK: Settings

struct ClipboardSettingsPane: View {
    @Bindable var settings: ClipboardSettings
    let registry: ModuleRegistry

    private var module: ClipboardModule? { registry.module(ClipboardModule.descriptor.id) as? ClipboardModule }

    var body: some View {
        Form {
            Section {
                Picker("History length", selection: $settings.historyLength) {
                    ForEach(ClipboardSettings.lengthChoices, id: \.self) { Text("\($0) items").tag($0) }
                }
                Toggle("Clear history when Notched quits", isOn: $settings.clearOnQuit)
                Button("Clear History", role: .destructive) { module?.clearHistory() }
                    .disabled(module == nil)
            } footer: {
                Text("Pinned items don't count toward the length and are kept when the history is cleared.")
            }

            Section {
                Toggle("Open with a keyboard shortcut", isOn: $settings.hotkeyEnabled)
                if settings.hotkeyEnabled {
                    KeyboardShortcuts.Recorder("Shortcut", name: .clipboardHistory)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("You can always open the history from the Clipboard tab or the Notched menu.")
            }

            Section {
                ForEach(settings.excludedApps, id: \.self) { bundleID in
                    LabeledContent(Self.name(for: bundleID)) {
                        Button("Remove", systemImage: "minus.circle") { settings.excludedApps.removeAll { $0 == bundleID } }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…", systemImage: "plus") { addApp() }
            } header: {
                Text("Never record copies from")
            } footer: {
                Text("This uses the app that was in front when you copied, so it can miss a copy made by a background app.")
            }

            Section {
                LabeledContent("Skipped always", value: "Items password managers mark as secret")
                LabeledContent("Not kept", value: "Text over 100 KB, images over 5 MB")
                LabeledContent("Stored", value: "On this Mac, in Application Support")
            } header: {
                Text("Privacy")
            } footer: {
                Text("The history is saved as plain files only you can read; it isn't encrypted, so don't copy anything you wouldn't want on disk, and use the exclusions or Clear on quit. Contents are never written to logs. macOS may ask whether Notched can read the clipboard; allow it, or the history stays empty. Notched never pastes for you.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Clipboard")
        .onChange(of: settings.historyLength) { module?.settingsChanged() }
        .onChange(of: settings.excludedApps) { module?.settingsChanged() }
        .onChange(of: settings.clearOnQuit) { module?.settingsChanged() }
        .onChange(of: settings.hotkeyEnabled) { module?.settingsChanged() }
    }

    private static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              !settings.excludedApps.contains(id) else { return }
        settings.excludedApps.append(id)
    }
}
