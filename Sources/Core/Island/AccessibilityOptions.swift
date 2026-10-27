// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation

/// The system's Reduce Motion, Reduce Transparency and Increase Contrast
/// settings, and whether the system appearance is dark (the island's keyline
/// shows only then), kept live. DEBUG builds can override them for screenshots.
@MainActor
@Observable
final class AccessibilityOptions {
    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false
    private(set) var isDarkAppearance = false

    #if DEBUG
    var overrideReduceMotion: Bool? { didSet { refresh() } }
    var overrideReduceTransparency: Bool? { didSet { refresh() } }
    var overrideIncreaseContrast: Bool? { didSet { refresh() } }
    #endif

    @ObservationIgnored private let observers = NotificationTokens()
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    init() {
        refresh()
        observers.observe(
            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            in: NSWorkspace.shared.notificationCenter
        ) { [weak self] in
            self?.refresh()
        }
        appearanceObservation = NSApp?.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
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
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDarkAppearance != dark { isDarkAppearance = dark }
    }
}
