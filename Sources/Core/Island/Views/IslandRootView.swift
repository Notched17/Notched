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
    }
}

/// The island: one shape, filled, with its content on top.
struct IslandView: View {
    let model: IslandViewModel

    var body: some View {
        let metrics = model.shapeMetrics
        let shape = IslandShape(
            shoulderRadius: metrics.shoulder,
            topCornerRadius: metrics.top,
            bottomCornerRadius: metrics.bottom
        )
        shape
            .fill(.black)
            .overlay { debugOutline(shape) }
            .frame(width: model.islandSize.width, height: model.islandSize.height)
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
