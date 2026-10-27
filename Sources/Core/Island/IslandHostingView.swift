// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Hosts the island's SwiftUI views.
///
/// - It never resizes its window: the controller owns the panel frame.
/// - It accepts the first click, so buttons work without activating the app.
/// - While expanded it reports the pointer leaving the island through one
///   `NSTrackingArea`, which costs nothing while the pointer is elsewhere
///   (no global mouse monitor). While compact, `IslandSensorPanel` does this.
final class IslandHostingView: NSHostingView<IslandRootView> {
    enum PointerEvent {
        case entered
        case exited
    }

    var onPointer: (PointerEvent) -> Void = { _ in }

    /// The island's rect in window coordinates.
    var trackingRectInWindow: CGRect = .zero {
        didSet { if trackingRectInWindow != oldValue { rebuildTrackingArea() } }
    }

    /// Re-arms tracking so the first event is an exit if the pointer is
    /// already inside (used when the island expands under the pointer).
    func resetTracking() {
        rebuildTrackingArea()
    }

    private var islandTrackingArea: NSTrackingArea?

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingArea()
    }

    private func rebuildTrackingArea() {
        if let islandTrackingArea { removeTrackingArea(islandTrackingArea) }
        let rect = convert(trackingRectInWindow, from: nil)
        guard !rect.isEmpty else { islandTrackingArea = nil; return }
        let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        islandTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === islandTrackingArea { onPointer(.entered) } else { super.mouseEntered(with: event) }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === islandTrackingArea { onPointer(.exited) } else { super.mouseExited(with: event) }
    }
}
