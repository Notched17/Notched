// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The first-run walkthrough (#77): welcome → choose modules → permissions
/// (only for the chosen modules) → done.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, modules, permissions, done

        init?(name: String) {
            guard let step = Self.allCases.first(where: { "\($0)" == name }) else { return nil }
            self = step
        }
    }

    let settings: SettingsStore
    let modules: [ModuleDescriptor]
    let permissions: PermissionCenter
    let scheduler: RefreshScheduler
    let launchAtLogin: LaunchAtLogin
    let finish: () -> Void

    init(settings: SettingsStore, modules: [ModuleDescriptor], permissions: PermissionCenter, scheduler: RefreshScheduler,
         launchAtLogin: LaunchAtLogin, startAt step: Step = .welcome, finish: @escaping () -> Void) {
        self.settings = settings
        self.modules = modules
        self.permissions = permissions
        self.scheduler = scheduler
        self.launchAtLogin = launchAtLogin
        self.finish = finish
        _step = State(initialValue: step)
    }

    @State private var step: Step
    @State private var openAtLogin = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .welcome: WelcomeStep(settings: settings)
                case .modules: ChooseModulesStep(settings: settings, modules: modules, permissions: permissions)
                case .permissions:
                    PermissionsStep(permissions: permissions, needed: neededPermissions, modules: chosenModules, scheduler: scheduler)
                case .done: DoneStep(openAtLogin: $openAtLogin)
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 24)),
                removal: .opacity.combined(with: .offset(x: -24))
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.xxl)

            footer
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
        }
        .frame(width: 560, height: 540)
    }

    private var footer: some View {
        HStack {
            Button("Back") { move(-1) }
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            HStack(spacing: Spacing.s) {
                ForEach(Step.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == step ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            Button(step == .done ? "Done" : "Continue") {
                if step == .done { complete() } else { move(1) }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    private var chosenModules: [ModuleDescriptor] {
        modules.filter { settings.enabledModules.contains($0.id) }
    }

    private var neededPermissions: [Permission] {
        Permission.requestedUpFront(by: chosenModules)
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(reduceMotion ? Motion.reduced : .smooth(duration: 0.35)) { step = next }
    }

    private func complete() {
        if openAtLogin != launchAtLogin.isEnabled { launchAtLogin.setEnabled(openAtLogin) }
        settings.hasCompletedOnboarding = true
        finish()
    }
}

/// A large title with a symbol and a short explanation.
struct OnboardingHeader: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.largeTitle, weight: .bold))
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
