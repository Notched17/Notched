// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Owns the panel and model for the island on one display.
@MainActor
final class IslandController {
    let displayID: DisplayID
    let model: IslandViewModel
    private let panel: IslandPanel
    private let hostingView: IslandHostingView

    init(displayID: DisplayID, geometry: NotchGeometry) {
        self.displayID = displayID
        model = IslandViewModel(geometry: geometry)
        let frame = model.panelFrame(for: model.presentation)
        panel = IslandPanel(contentRect: frame)
        hostingView = IslandHostingView(rootView: IslandRootView(model: model))
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        Log.island.info("Island on \(displayID, privacy: .public): \(String(describing: geometry.kind), privacy: .public) panel \(NSStringFromRect(frame), privacy: .public)")
    }

    func update(geometry: NotchGeometry) {
        guard geometry != model.geometry else { return }
        model.geometry = geometry
        let frame = model.panelFrame(for: model.presentation)
        panel.setFrame(frame, display: true)
        Log.island.info("Island on \(self.displayID, privacy: .public) moved to \(NSStringFromRect(frame), privacy: .public)")
    }

    func tearDown() {
        panel.orderOut(nil)
        panel.close()
    }
}
