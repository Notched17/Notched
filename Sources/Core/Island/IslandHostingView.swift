// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Hosts the island's SwiftUI views. It never resizes its window (the
/// controller owns the panel frame) and accepts the first click, so buttons
/// work without activating the app.
final class IslandHostingView: NSHostingView<IslandRootView> {
    required init(rootView: IslandRootView) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
