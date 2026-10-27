// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Fills the island panel and pins the island to its top centre.
struct IslandRootView: View {
    let model: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            IslandView(model: model)
            Spacer(minLength: 0)
        }
        .padding(.top, model.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

/// The island: one continuously morphing shape with its content on top.
struct IslandView: View {
    let model: IslandViewModel

    var body: some View {
        let metrics = model.shapeMetrics
        let shape = IslandShape(
            shoulderRadius: metrics.shoulder,
            topCornerRadius: metrics.top,
            bottomCornerRadius: metrics.bottom
        )
        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .contentShape(shape)
                .onTapGesture { model.onSurfaceTap() }

            if model.presentation == .expanded {
                ExpandedContentView(model: model)
                    .transition(Motion.expandedContent(reduceMotion: model.accessibility.reduceMotion))
            }
        }
        .frame(width: model.islandSize.width, height: model.islandSize.height)
        .clipShape(shape)
        .background {
            // A soft shadow lifts the expanded island off bright windows. Never
            // on the compact notch, where it would reveal the island.
            shape
                .fill(.black)
                .shadow(color: .black.opacity(showsShadow ? 0.32 : 0), radius: 12, y: 6)
        }
        .overlay { contrastOutline(shape) }
        .overlay { debugOutline(shape) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DynamicNotch")
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
