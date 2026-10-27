// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation

/// The system's Reduce Motion, Reduce Transparency and Increase Contrast
/// settings, kept live. DEBUG builds can override them for screenshots.
@MainActor
@Observable
final class AccessibilityOptions {
    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false

    #if DEBUG
    var overrideReduceMotion: Bool? { didSet { refresh() } }
    var overrideReduceTransparency: Bool? { didSet { refresh() } }
    var overrideIncreaseContrast: Bool? { didSet { refresh() } }
    #endif

    @ObservationIgnored private let observers = NotificationTokens()

    init() {
        refresh()
        observers.observe(
            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            in: NSWorkspace.shared.notificationCenter
        ) { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        let workspace = NSWorkspace.shared
        var motion = workspace.accessibilityDisplayShouldReduceMotion
        var transparency = workspace.accessibilityDisplayShouldReduceTransparency
        var contrast = workspace.accessibilityDisplayShouldIncreaseContrast
        #if DEBUG
        motion = overrideReduceMotion ?? motion
        transparency = overrideReduceTransparency ?? transparency
        contrast = overrideIncreaseContrast ?? contrast
        #endif
        if reduceMotion != motion { reduceMotion = motion }
        if reduceTransparency != transparency { reduceTransparency = transparency }
        if increaseContrast != contrast { increaseContrast = contrast }
    }
}
