// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Live status of every privacy permission DynamicNotch can use, which
/// modules need it, and a shortcut to the right System Settings pane (#77).
struct PermissionsPane: View {
    let permissions: PermissionCenter
    let modules: [ModuleDescriptor]
    let settings: SettingsStore
    let scheduler: RefreshScheduler

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    PermissionRow(
                        permission: permission,
                        status: permissions.status(permission),
                        neededBy: modules.filter { settings.enabledModules.contains($0.id) && $0.permissions.contains(permission) },
                        open: { permissions.openSystemSettings(for: permission) }
                    )
                }
            } footer: {
                Text("DynamicNotch only asks for a permission when you turn on a module that needs it. You can change any of these in System Settings > Privacy & Security.")
            }
        }
        .formStyle(.grouped)
        .onAppear { scheduler.setUIVisible(PermissionCenter.liveUpdatesKey, true); permissions.refresh() }
        .onDisappear { scheduler.setUIVisible(PermissionCenter.liveUpdatesKey, false) }
    }
}

struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let neededBy: [ModuleDescriptor]
    let open: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.m) {
                PermissionStatusBadge(status: status)
                Button("Open…", action: open)
                    .controlSize(.small)
                    .help("Open \(permission.title) in System Settings")
            }
        } label: {
            HStack(alignment: .top, spacing: Spacing.m) {
                SettingsIcon(symbol: permission.symbol, tint: .blue, size: 24)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(permission.title)
                    Text(neededBy.isEmpty ? permission.purpose : "Needed by \(neededBy.map(\.name).formatted(.list(type: .and))).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.title)
    }
}

struct PermissionStatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        Label(status.title, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(tint)
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect(.replace))
    }

    private var symbol: String {
        switch status {
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .notDetermined: "circle.dashed"
        case .off: "circle"
        case .perApp: "app.badge.checkmark"
        }
    }

    private var tint: Color {
        switch status {
        case .granted: .green
        case .denied: .red
        case .notDetermined, .off, .perApp: .secondary
        }
    }
}
