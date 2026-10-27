// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The compact island's two slots, either side of the notch (or of the pill's centre).
struct CompactContentView: View {
    let model: IslandViewModel

    var body: some View {
        // Like iPhone's Dynamic Island: each slot hugs its outer edge, with
        // equal margins, and keeps a small gap from the notch.
        let side = model.compactSideWidth
        let inner = IslandMetrics.compactSlotInnerGap
        let outer = max(IslandMetrics.compactSlotPadding - inner, 0)
        HStack(spacing: 0) {
            slot(model.activities.leading)
                .frame(width: max(side - outer - inner, 0), alignment: .leading)
                .padding(.leading, outer)
                .padding(.trailing, inner)
            Color.clear
                .frame(width: model.geometry.compactBaseSize.width)
            slot(model.activities.trailing)
                .frame(width: max(side - outer - inner, 0), alignment: .trailing)
                .padding(.leading, inner)
                .padding(.trailing, outer)
        }
        .frame(height: model.geometry.compactBaseSize.height)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func slot(_ slot: ActivityCoordinator.Slot?) -> some View {
        ZStack {
            if let slot {
                slot.content.view()
                    .id(slot.activityID)
                    .transition(Motion.contentSwap)
                    .accessibilityLabel(slot.content.accessibilityLabel)
            }
        }
    }
}
