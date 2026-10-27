// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A live, scaled-down island (#72) that uses the same views, shape, theme,
/// springs and hover delay as the real one, so settings can be tried at once.
struct IslandPreview: View {
    let settings: SettingsStore
    @State private var model: IslandViewModel
    @State private var pendingExpand: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(settings: SettingsStore) {
        self.settings = settings
        _model = State(initialValue: IslandViewModel(
            geometry: Self.geometry(for: settings),
            accessibility: AccessibilityOptions(),
            activities: ActivityCoordinator()
        ))
    }

    var body: some View {
        let stage = CGSize(width: model.expandedSize.width + 80, height: model.expandedSize.height + 36)
        VStack(spacing: Spacing.m) {
            GeometryReader { proxy in
                let scale = proxy.size.width / stage.width
                ZStack(alignment: .top) {
                    backdrop
                    IslandView(model: model)
                        .padding(.top, model.geometry.kind == .pill ? 30 : 0)
                }
                .frame(width: stage.width, height: stage.height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(scale, anchor: .topLeading)
            }
            .aspectRatio(stage.width / stage.height, contentMode: .fit)
            .frame(maxWidth: 480)
            .onHover(perform: hover)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Island preview")

            Button("Replay", systemImage: "play.fill", action: replay)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.vertical, Spacing.xs)
        .onChange(of: settings.notchTheme) { refresh() }
        .onChange(of: settings.pillTheme) { refresh() }
        .onChange(of: settings.widthOffset) { refresh() }
        .onChange(of: settings.expandedScale) { refresh() }
        .onChange(of: settings.animationStyle) { replay() }
        .onAppear(perform: refresh)
        .onDisappear { pendingExpand?.cancel() }
    }

    /// A simple desktop: wallpaper-like gradient and a menu-bar strip.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.indigo.opacity(0.85), .teal.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle()
                .fill(.black.opacity(0.18))
                .frame(height: model.geometry.kind == .notch ? model.geometry.compactBaseSize.height : 24)
        }
    }

    private func refresh() {
        model.geometry = Self.geometry(for: settings)
        model.theme = settings.theme(for: model.geometry.kind)
        model.expandedSize = IslandAppearance(expandedScale: settings.expandedScale).expandedSize
    }

    private func hover(_ inside: Bool) {
        pendingExpand?.cancel()
        if inside {
            let delay = settings.hoverDelay
            pendingExpand = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                present(.expanded)
            }
        } else {
            present(.compact)
        }
    }

    private func replay() {
        pendingExpand?.cancel()
        present(.expanded)
        pendingExpand = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            present(.compact)
        }
    }

    private func present(_ presentation: IslandPresentation) {
        let style = settings.animationStyle
        let animation = reduceMotion ? Motion.reduced : (presentation == .expanded ? style.expand : style.collapse)
        withAnimation(animation) { model.presentation = presentation }
    }

    /// The real main display's geometry, so the preview matches this Mac.
    private static func geometry(for settings: SettingsStore) -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.isBuiltIn && $0.hasNotch } ?? NSScreen.screens.first
        var forcePill = false
        #if DEBUG
        forcePill = settings.debugForcePill
        #endif
        guard let screen else {
            return NotchGeometry.resolve(ScreenDescriptor(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 958),
                safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, backingScale: 2
            ))
        }
        return NotchGeometry.resolve(screen.screenDescriptor, widthOffset: settings.widthOffset, forcePill: forcePill)
    }
}
