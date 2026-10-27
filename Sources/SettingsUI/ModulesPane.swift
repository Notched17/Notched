// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Every module with an on/off switch, its description and the permissions
/// it needs (#70). Modules are off until turned on here or in onboarding.
struct ModulesPane: View {
    @Bindable var settings: SettingsStore
    let modules: [ModuleDescriptor]

    var body: some View {
        Form {
            if modules.isEmpty {
                Section {
                    ContentUnavailableView(
                        "More Modules Are Coming",
                        systemImage: "square.grid.2x2",
                        description: Text("Now Playing, battery, calendar and more arrive in upcoming versions. Each one stays off until you turn it on.")
                    )
                }
            } else {
                Section {
                    ForEach(modules) { module in
                        ModuleRow(module: module, isOn: binding(for: module.id))
                    }
                } footer: {
                    Text("A module that's off uses no energy at all. Permissions are only requested when you turn on a module that needs them.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for id: ModuleID) -> Binding<Bool> {
        Binding(
            get: { settings.enabledModules.contains(id) },
            set: { isOn in
                if isOn { settings.enabledModules.insert(id) } else { settings.enabledModules.remove(id) }
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
