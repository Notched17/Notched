// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The compact island's two sides, either side of the notch (or of the pill's
/// centre). Both always show the same activity (or banner).
struct CompactContentView: View {
    let model: IslandViewModel

    var body: some View {
        let side = model.compactSideWidth
        let inner = IslandMetrics.compactSlotInnerGap
        let outer = max(IslandMetrics.compactSlotPadding - inner, 0)
        let content = model.compactContent
        HStack(spacing: 0) {
            region(content?.leading, id: content?.id, isLeading: true)
                .frame(width: max(side - outer - inner, 0), alignment: .leading)
                .padding(.leading, outer)
                .padding(.trailing, inner)
            Color.clear
                .frame(width: model.geometry.compactBaseSize.width)
            region(content?.trailing, id: content?.id, isLeading: false)
                .frame(width: max(side - outer - inner, 0), alignment: .trailing)
                .padding(.leading, inner)
                .padding(.trailing, outer)
        }
        .frame(height: model.geometry.compactBaseSize.height)
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content?.accessibilityLabel ?? "")
    }

    @ViewBuilder
    private func region(_ region: IslandRegion?, id: String?, isLeading: Bool) -> some View {
        ZStack {
            if let region, let id {
                IslandRegionHost(revision: model.compactRevision, isStale: model.compactIsStale) {
                    region.view()
                }
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        model.reportCompactWidth(width, for: id, leading: isLeading)
                    }
                    .id(id)
                    .transition(Motion.contentSwap)
            }
        }
    }
}
