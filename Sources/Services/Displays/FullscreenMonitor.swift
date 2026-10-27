// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Knows which displays are currently showing a fullscreen app (#5).
///
/// Event-driven: it re-checks when the active Space changes, an app activates
/// or the screens change, plus once more shortly afterwards to catch the end
/// of the fullscreen transition. Native fullscreen Spaces come from SkyLight
/// (ADR-0003); borderless fullscreen windows such as games come from the
/// public window list. Either one counts.
@MainActor
final class FullscreenMonitor {
    private(set) var fullscreenDisplays: Set<DisplayID> = []
    var onChange: (Set<DisplayID>) -> Void = { _ in }

    #if DEBUG
    /// Ignore SkyLight and use only the public fallback.
    var forceFallback = false { didSet { refresh() } }
    #endif

    private let observers = NotificationTokens()
    private var recheck: Task<Void, Never>?

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.observe(NSWorkspace.activeSpaceDidChangeNotification, in: workspace) { [weak self] in
            self?.refreshSoon()
        }
        observers.observe(NSWorkspace.didActivateApplicationNotification, in: workspace) { [weak self] in
            self?.refreshSoon()
        }
        observers.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.refreshSoon()
        }
        refresh()
    }

    func stop() {
        observers.invalidate()
        recheck?.cancel()
    }

    private func refreshSoon() {
        refresh()
        recheck?.cancel()
        recheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        var detected = WindowListFullscreenHeuristic.current()
        var useSkyLight = true
        #if DEBUG
        useSkyLight = !forceFallback
        #endif
        if useSkyLight, let snapshot = SkyLightSpaces.managedDisplaySpaces() {
            detected.formUnion(ManagedSpaces.fullscreenDisplays(in: snapshot, mainDisplay: NSScreen.screens.first?.displayID))
        }
        guard detected != fullscreenDisplays else { return }
        fullscreenDisplays = detected
        Log.displays.info("Fullscreen displays: \(detected.map(\.rawValue).sorted().joined(separator: ", "), privacy: .public)")
        onChange(detected)
    }
}
