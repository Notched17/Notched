// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Every module with an on/off switch, its description and the permissions
/// it needs (#70). Modules that need a permission are off until turned on.
struct ModulesPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var navigation: SettingsNavigation
    let modules: [ModuleDescriptor]
    let registry: ModuleRegistry
    let permissions: PermissionCenter

    var body: some View {
        NavigationStack(path: $navigation.modulePath) {
            form
                .navigationTitle(SettingsPane.modules.title)
                .navigationDestination(for: ModuleID.self) { id in
                    registry.settingsPane(for: id)
                        .navigationBarBackButtonHidden()
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button("Modules", systemImage: "chevron.left") { navigation.modulePath.removeAll() }
                                    .help("Back to Modules")
                            }
                        }
                }
        }
    }

    private var form: some View {
        Form {
            if modules.isEmpty {
                Section {
                    ContentUnavailableView(
                        "More Modules Are Coming",
                        systemImage: "square.grid.2x2",
                        description: Text("Now Playing, battery, calendar and more arrive in upcoming versions. Anything that needs a permission stays off until you turn it on.")
                    )
                }
            } else {
                if registry.isSafeMode {
                    Section {
                        LabeledContent {
                            Button("Resume Modules") { registry.leaveSafeMode() }
                                .accessibilityLabel("Resume Modules")
                        } label: {
                            Label("Modules are paused", systemImage: "exclamationmark.triangle.fill")
                            Text("Notched quit unexpectedly several times just after opening, so it started without any modules.")
                        }
                    }
                }
                Section {
                    ForEach(modules) { module in
                        ModuleRow(module: module, isOn: ModuleToggle.binding(for: module, settings: settings, permissions: permissions,
                                                                             registry: registry))
                            // Nothing runs in safe mode; Resume Modules above is the way out.
                            .disabled(registry.isSafeMode)
                        if registry.suspendedIDs.contains(module.id) {
                            LabeledContent {
                                Button("Turn On") { registry.resume(module.id) }
                                    .accessibilityLabel("Turn \(module.name) Back On")
                            } label: {
                                Label("Turned off", systemImage: "exclamationmark.triangle.fill")
                                Text("\(module.name) quit unexpectedly while starting, twice.")
                            }
                            .symbolRenderingMode(.multicolor)
                        }
                        if registry.hasSettingsPane(module.id) {
                            NavigationLink(value: module.id) {
                                Text("\(module.name) Options")
                            }
                        }
                    }
                } footer: {
                    Text("A module that's off uses no energy at all. Permissions are only requested when you turn on a module that needs them.")
                }
            }
        }
        .formStyle(.grouped)
    }

}

/// Turning a module on asks for the permissions it needs, and only then.
/// A module suspended after crashing shows as off; turning it on resumes it.
@MainActor
enum ModuleToggle {
    static func binding(for module: ModuleDescriptor, settings: SettingsStore, permissions: PermissionCenter,
                        registry: ModuleRegistry? = nil) -> Binding<Bool> {
        Binding(
            get: { settings.enabledModules.contains(module.id) && registry?.suspendedIDs.contains(module.id) != true },
            set: { isOn in
                guard isOn else { settings.enabledModules.remove(module.id); return }
                if registry?.suspendedIDs.contains(module.id) == true { registry?.resume(module.id) }
                settings.enabledModules.insert(module.id)
                Task {
                    for permission in Permission.requestedUpFront(by: [module]) where permissions.status(permission) != .granted {
                        await permissions.request(permission)
                    }
                }
            }
        )
    }
}

struct ModuleRow: View {
    let module: ModuleDescriptor
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: Spacing.m) {
                SettingsIcon(symbol: module.symbol, tint: .orange, size: 28)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.s) {
                        Text(module.name)
                        if module.isDebugOnly {
                            Text("Debug").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, Spacing.xs).background(.quaternary, in: Capsule())
                        }
                    }
                    Text(module.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !module.permissions.isEmpty {
                        HStack(spacing: Spacing.xs) {
                            ForEach(module.permissions) { permission in
                                Label(permission.title, systemImage: permission.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .toggleStyle(.switch)
    }
}
