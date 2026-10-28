// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct WelcomeStep: View {
    let settings: SettingsStore

    var body: some View {
        VStack(spacing: Spacing.xl) {
            WelcomeIsland()
            VStack(spacing: Spacing.s) {
                Text("Welcome to Notched")
                    .font(.system(.largeTitle, weight: .bold))
                Text("Your Mac's notch, alive with what's happening.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Spacing.m) {
                WelcomeFeature(symbol: "capsule.fill", title: "Lives in the notch", detail: "Rest the pointer on the notch, or click it, to open the island.")
                WelcomeFeature(symbol: "leaf.fill", title: "Light on battery", detail: "Nothing runs unless it needs to.")
                WelcomeFeature(symbol: "hand.raised.fill", title: "Yours to choose", detail: "Modules that need a permission stay off until you turn them on.")
            }
            .frame(maxWidth: 400)
        }
    }
}

/// The island morphing on its own, as a greeting. Stops with Reduce Motion,
/// and whenever the window isn't active, so a forgotten onboarding window
/// costs no CPU.
private struct WelcomeIsland: View {
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        let shape = IslandShape(
            shoulderRadius: expanded ? 10 : 5,
            topCornerRadius: 0,
            bottomCornerRadius: expanded ? 22 : 9
        )
        ZStack(alignment: .top) {
            // A small screen for the island to hang from.
            LinearGradient(colors: [.indigo.opacity(0.85), .teal.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.18)).frame(height: 26) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            shape
                .fill(.black)
                .frame(width: expanded ? 300 : 120, height: expanded ? 86 : 26)
                .overlay(alignment: .top) {
                    if expanded {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "hand.wave.fill").symbolRenderingMode(.hierarchical)
                            Text("Hello").fontWeight(.semibold)
                        }
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 34)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
        }
        .frame(width: 360, height: 120, alignment: .top)
        .task(id: appearsActive) {
            guard !reduceMotion, appearsActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(expanded ? AnimationStyle.smooth.collapse : AnimationStyle.smooth.expand) { expanded.toggle() }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WelcomeFeature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChooseModulesStep: View {
    @Bindable var settings: SettingsStore
    let modules: [ModuleDescriptor]
    let permissions: PermissionCenter

    var body: some View {
        VStack(spacing: Spacing.xl) {
            OnboardingHeader(
                symbol: "square.grid.2x2.fill",
                title: "Choose Modules",
                message: "Pick what the island shows. You can change this any time in Settings."
            )
            if modules.isEmpty {
                ContentUnavailableView(
                    "More Modules Are Coming",
                    systemImage: "sparkles",
                    description: Text("This first version is the island itself. Now Playing, battery, calendar and more arrive soon.")
                )
            } else {
                Form {
                    ForEach(modules) { module in
                        ModuleRow(module: module, isOn: ModuleToggle.binding(for: module, settings: settings, permissions: permissions))
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

struct PermissionsStep: View {
    let permissions: PermissionCenter
    let needed: [Permission]
    let modules: [ModuleDescriptor]
    let scheduler: RefreshScheduler

    var body: some View {
        VStack(spacing: Spacing.xl) {
            if needed.isEmpty {
                OnboardingHeader(
                    symbol: "checkmark.shield.fill",
                    title: "Nothing to Allow",
                    message: "The modules you chose don't need any extra permissions."
                )
                Spacer()
            } else {
                OnboardingHeader(
                    symbol: "hand.raised.fill",
                    title: "Permissions",
                    message: "Your modules need these to work. macOS will ask you to confirm each one."
                )
                Form {
                    ForEach(needed) { permission in
                        LabeledContent {
                            if permissions.status(permission) == .granted {
                                PermissionStatusBadge(status: .granted)
                            } else {
                                Button("Allow…") { Task { await permissions.request(permission) } }
                            }
                        } label: {
                            Label(permission.title, systemImage: permission.symbol)
                            Text(permission.purpose)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
        .onAppear { scheduler.setUIVisible(PermissionCenter.liveUpdatesKey, true) }
        .onDisappear { scheduler.setUIVisible(PermissionCenter.liveUpdatesKey, false) }
    }
}

struct DoneStep: View {
    @Binding var openAtLogin: Bool

    var body: some View {
        VStack(spacing: Spacing.xl) {
            OnboardingHeader(
                symbol: "checkmark.circle.fill",
                title: "You're All Set",
                message: "Rest the pointer on the notch to open the island. Settings live in the menu bar."
            )
            Form {
                Toggle("Open Notched at login", isOn: $openAtLogin)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: 90)
            Spacer()
        }
    }
}
