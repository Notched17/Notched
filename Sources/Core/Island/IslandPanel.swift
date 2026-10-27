// SPDX-License-Identifier: GPL-3.0-or-later
//
// Panel configuration adapted from TheBoredTeam/boring.notch's BoringNotchWindow
// (GPL-3.0). See THIRD_PARTY_NOTICES.md.

import AppKit

/// The borderless, transparent, non-activating panel that hosts one island.
/// It floats above the menu bar on every Space, including fullscreen ones.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Hide the island from screenshots and screen sharing (#6). Capture tools
    /// built on ScreenCaptureKit may ignore this.
    var hiddenFromCapture = false {
        didSet { sharingType = hiddenFromCapture ? .none : .readOnly }
    }
}
