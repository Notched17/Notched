// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// An invisible window exactly over the compact island. While the island is
/// compact the main island panel ignores the mouse entirely (so everything
/// beside it stays clickable), and this sensor detects hover and clicks.
///
/// Resizing an invisible window has no visual cost, which is why hover
/// detection lives here instead of in a resizing island panel (ADR-0002).
final class IslandSensorPanel: NSPanel {
    enum Event {
        case entered
        /// The pointer's screen position when the exit was reported.
        case exited(CGPoint)
        case clicked
    }

    private let sensorView = SensorView()

    var onEvent: (Event) -> Void {
        get { sensorView.onEvent }
        set { sensorView.onEvent = newValue }
    }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Just below the island panel, so the island wins whenever it accepts the mouse.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = false
        sharingType = .none
        contentView = sensorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Keep the frame exactly as set: the notch island deliberately reaches a
    /// couple of points past the top of the screen (see `topEdgeOverscan`).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Re-arms tracking, e.g. after the island collapses under a still pointer.
    func resetTracking() {
        sensorView.rebuildTrackingArea()
    }
}

private final class SensorView: NSView {
    var onEvent: (IslandSensorPanel.Event) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingArea()
    }

    func rebuildTrackingArea() {
        if let area { removeTrackingArea(area) }
        let newArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(newArea)
        area = newArea
    }

    override func mouseEntered(with event: NSEvent) { onEvent(.entered) }
    // The event's own location can be relative to the overlapping island
    // panel, so report where the pointer actually is.
    override func mouseExited(with event: NSEvent) { onEvent(.exited(NSEvent.mouseLocation)) }
    override func mouseDown(with event: NSEvent) { onEvent(.clicked) }
}
