// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The panes of the Settings window, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, appearance, modules, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .modules: "Modules"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .modules: "square.grid.2x2.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }

    /// Icon colours in the style of System Settings.
    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .indigo
        case .modules: .orange
        case .permissions: .blue
        case .about: .secondary
        }
    }
}

/// Which pane the Settings window shows; set from outside to deep-link.
@MainActor
@Observable
final class SettingsNavigation {
    var selection: SettingsPane = .general
    /// A module's settings pane open inside Modules, e.g. Now Playing Options.
    var modulePath: [ModuleID] = []
}

/// What the panes need from the rest of the app.
@MainActor
struct SettingsContext {
    let settings: SettingsStore
    let modules: [ModuleDescriptor]
    let registry: ModuleRegistry
    let permissions: PermissionCenter
    let scheduler: RefreshScheduler
    let launchAtLogin: LaunchAtLogin
    let accessibility: AccessibilityOptions
    var showWelcome: () -> Void = {}
}

struct SettingsRootView: View {
    let navigation: SettingsNavigation
    let context: SettingsContext

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(symbol: pane.symbol, tint: pane.tint)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            if navigation.selection == .modules {
                // Modules titles its own navigation stack (a module's options page pushes onto it).
                detail
            } else {
                detail
                    .navigationTitle(navigation.selection.title)
            }
        }
    }

    private var selection: Binding<SettingsPane?> {
        Binding(get: { navigation.selection }, set: { if let pane = $0 { navigation.selection = pane } })
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection {
        case .general: GeneralPane(settings: context.settings, launchAtLogin: context.launchAtLogin)
        case .appearance: AppearancePane(settings: context.settings, accessibility: context.accessibility)
        case .modules:
            ModulesPane(settings: context.settings, navigation: navigation, modules: context.modules, registry: context.registry,
                        permissions: context.permissions)
        case .permissions:
            PermissionsPane(permissions: context.permissions, modules: context.modules, settings: context.settings, scheduler: context.scheduler)
        case .about: AboutPane(showWelcome: context.showWelcome)
        }
    }
}

/// A white SF Symbol on a coloured rounded square, like System Settings.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}
