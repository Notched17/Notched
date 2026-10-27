// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Fills the island panel and places the island and its minimal bubbles at
/// their screen positions. The compact island can be asymmetric (an empty
/// trailing side hides), so it is placed by its frame rather than centred.
struct IslandRootView: View {
    let model: IslandViewModel

    var body: some View {
        let panel = model.panelFrame
        let island = model.islandRect(for: model.presentation)
        ZStack(alignment: .topLeading) {
            // Bubbles sit under the island, so they bud out from beneath its
            // edge and slip back under it to merge.
            MinimalBubblesView(model: model, panel: panel)
            IslandView(model: model)
                .offset(x: island.minX - panel.minX, y: panel.maxY - island.maxY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(layoutAnimation, value: model.compactLayout)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        // The island panel is never the key window, but its controls are live:
        // draw them active rather than in the dimmed inactive-window look.
        .environment(\.controlActiveState, .key)
    }

    private var layoutAnimation: Animation {
        model.accessibility.reduceMotion ? Motion.reduced : .spring(response: 0.36, dampingFraction: 0.8)
    }
}

/// The island: one continuously morphing shape with its content on top.
struct IslandView: View {
    let model: IslandViewModel
    @Namespace private var namespace

    var body: some View {
        let metrics = model.shapeMetrics
        let shape = IslandShape(
            shoulderRadius: metrics.shoulder,
            topCornerRadius: metrics.top,
            bottomCornerRadius: metrics.bottom
        )
        ZStack(alignment: .top) {
            IslandSolidFill(shape: shape, model: model)
                .contentShape(shape)
                .onTapGesture { model.onSurfaceTap() }

            if model.presentation == .compact {
                CompactContentView(model: model)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            } else {
                ExpandedContentView(model: model)
                    .transition(Motion.expandedContent(reduceMotion: model.accessibility.reduceMotion))
            }
        }
        .environment(\.islandNamespace, namespace)
        .frame(width: model.islandSize.width, height: model.islandSize.height)
        .animation(resizeAnimation, value: model.expandedHeight)
        .environment(\.islandReduceMotion, model.accessibility.reduceMotion)
        .environment(\.islandSurfaceIsGlass, model.surfaceIsGlass)
        .clipShape(shape)
        // Glass goes after layout and around the content, so the content gets
        // glass vibrancy. Disabled (black) on the compact notch.
        .glassEffect(model.surfaceIsGlass ? model.theme.glass : .identity, in: shape)
        .background {
            // A soft shadow lifts the expanded island off bright windows. Never
            // on the compact notch, where it would reveal the island, and not
            // under glass, which brings its own.
            if !model.surfaceIsGlass {
                shape
                    .fill(.black)
                    .shadow(color: .black.opacity(showsShadow ? 0.32 : 0), radius: 12, y: 6)
            }
        }
        .overlay { contrastOutline(shape) }
        .overlay { debugOutline(shape) }
        .modifier(AlertBounce(trigger: model.activities.bounceSerial, enabled: !model.accessibility.reduceMotion))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notched")
    }

    private var resizeAnimation: Animation {
        model.accessibility.reduceMotion ? Motion.reduced : Motion.resize
    }

    private var showsShadow: Bool {
        model.presentation == .expanded || model.geometry.kind == .pill
    }

    /// With Increase Contrast, a hairline makes the expanded island's edge
    /// visible against dark backgrounds. Never on the compact notch, where it
    /// would outline the camera housing.
    @ViewBuilder
    private func contrastOutline(_ shape: IslandShape) -> some View {
        if model.accessibility.increaseContrast,
           model.presentation == .expanded || model.geometry.kind == .pill {
            shape.stroke(.white.opacity(0.35), lineWidth: 1)
        } else if model.showsExpandedKeyline {
            // The keyline (ISLAND-BEHAVIOR.md §4): a subtle tinted border in dark surroundings.
            shape.stroke((model.expandedActivity?.activity.keylineTint ?? .white).opacity(0.28), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func debugOutline(_ shape: IslandShape) -> some View {
        #if DEBUG
        if model.debugOutline {
            shape.stroke(.red, lineWidth: 0.5)
        }
        #endif
    }
}

/// A tiny bounce when a new alert arrives. Off with Reduce Motion.
private struct AlertBounce: ViewModifier {
    let trigger: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
            view.scaleEffect(scale, anchor: .top)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(enabled ? 1.05 : 1, duration: 0.14, spring: .snappy)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
            }
        }
    }
}
