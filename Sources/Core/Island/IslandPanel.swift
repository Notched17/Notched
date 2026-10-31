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

    /// The panel only takes keyboard focus after a click inside the expanded
    /// island, so Esc can collapse it. Hovering never steals typing from the
    /// user's app.
    var allowsKey = false
    /// Esc while the panel has focus.
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// A tab that types keys itself is showing (the Terminal): Esc and the
    /// arrow keys are its own, and ⌘C/⌘V/⌘A are forwarded to it.
    var contentOwnsKeyboard = false

    override func cancelOperation(_ sender: Any?) {
        // ⌘. also arrives here; with the shell in front it means nothing.
        if !contentOwnsKeyboard { onCancel() }
    }

    /// Tab and page keys while the panel has focus. True when handled.
    var onKeyCommand: (ExpandedKeyCommand) -> Bool = { _ in false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            // Reached only if the content didn't take it.
            if IslandKeyboardPolicy.escape(capturesKeyboard: contentOwnsKeyboard, command: event.modifierFlags.contains(.command)) == .collapse {
                onCancel()
            }
        } else if !route(event) {
            super.keyDown(with: event)
        }
    }

    /// ⌘1…⌘5 arrive as key equivalents before `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        if isKeyWindow, event.keyCode == 53, flags.contains(.command) {
            onCancel()   // ⌘Esc collapses, whatever is in front
            return true
        }
        if isKeyWindow, let edit = IslandKeyboardPolicy.editCommand(
            characters: event.charactersIgnoringModifiers, command: flags.contains(.command), control: flags.contains(.control),
            shift: flags.contains(.shift), option: flags.contains(.option), capturesKeyboard: contentOwnsKeyboard
        ) {
            let action: Selector = switch edit {
            case .copy: #selector(NSText.copy(_:))
            case .paste: #selector(NSText.paste(_:))
            case .selectAll: #selector(NSText.selectAll(_:))
            }
            // To the first responder, i.e. the terminal.
            return NSApp.sendAction(action, to: nil, from: self)
        }
        return route(event) || super.performKeyEquivalent(with: event)
    }

    private func route(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard isKeyWindow, let command = ExpandedTabs.command(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
            command: flags.contains(.command), control: flags.contains(.control),
            shift: flags.contains(.shift), option: flags.contains(.option), capturesKeyboard: contentOwnsKeyboard
        ) else { return false }
        return onKeyCommand(command)
    }

    /// Keep the frame exactly as set: the notch island deliberately reaches a
    /// couple of points past the top of the screen (see `topEdgeOverscan`).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Hide the island from screenshots and screen sharing (#6). Capture tools
    /// built on ScreenCaptureKit may ignore this.
    var hiddenFromCapture = false {
        didSet { sharingType = hiddenFromCapture ? .none : .readOnly }
    }
}
