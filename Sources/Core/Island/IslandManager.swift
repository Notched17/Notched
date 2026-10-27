// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The settings that decide which displays show an island and how it's placed.
struct IslandConfiguration: Equatable, Sendable {
    var displaySelection: DisplaySelection = .main
    var widthOffset: CGFloat = 0
    /// Debug aid: show the pill even on a notched display.
    var forcePill = false
}

/// Keeps one `IslandController` per selected display, in sync with the
/// connected screens, their resolutions, sleep/wake and the configuration.
@MainActor
final class IslandManager {
    private(set) var controllers: [DisplayID: IslandController] = [:]

    var configuration: IslandConfiguration {
        didSet { if configuration != oldValue { reconcileScreens() } }
    }

    var behavior: IslandBehavior {
        didSet { for controller in controllers.values { controller.behavior = behavior } }
    }

    /// Pause hides every island until resumed (status menu or Settings).
    var isPaused = false {
        didSet { if isPaused != oldValue { applyVisibility() } }
    }

    var hideFromScreenCapture = false {
        didSet { for controller in controllers.values { controller.setHiddenFromCapture(hideFromScreenCapture) } }
    }

    let accessibility: AccessibilityOptions
    var actions = IslandActions()
    var onPauseChanged: (Bool) -> Void = { _ in }

    private let observers = NotificationTokens()
    private var pendingReconcile: Task<Void, Never>?

    init(configuration: IslandConfiguration = IslandConfiguration(),
         behavior: IslandBehavior = IslandBehavior(),
         accessibility: AccessibilityOptions) {
        self.configuration = configuration
        self.behavior = behavior
        self.accessibility = accessibility
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.scheduleReconcile()
        }
        observers.observe(NSWorkspace.didWakeNotification, in: workspace) { [weak self] in
            self?.scheduleReconcile()
        }
        observers.observe(NSWorkspace.screensDidWakeNotification, in: workspace) { [weak self] in
            self?.scheduleReconcile()
        }
        reconcileScreens()
    }

    func stop() {
        observers.invalidate()
        pendingReconcile?.cancel()
        for controller in controllers.values { controller.tearDown() }
        controllers.removeAll()
    }

    func expandAll() { for controller in controllers.values { controller.expand() } }
    func collapseAll() { for controller in controllers.values { controller.collapse() } }

    /// Screen notifications arrive in bursts; settle for 200 ms before rebuilding.
    private func scheduleReconcile() {
        pendingReconcile?.cancel()
        pendingReconcile = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.reconcileScreens()
        }
    }

    func reconcileScreens() {
        let screens = NSScreen.screens.compactMap { screen in screen.displayID.map { (id: $0, screen: screen) } }
        let candidates = screens.map { DisplayCandidate(id: $0.id, isBuiltIn: $0.screen.isBuiltIn, hasNotch: $0.screen.hasNotch) }
        let wanted = Set(configuration.displaySelection.resolve(among: candidates))

        for (id, controller) in controllers where !wanted.contains(id) {
            controller.tearDown()
            controllers[id] = nil
            Log.displays.info("Removed island from \(id, privacy: .public)")
        }
        for (id, screen) in screens where wanted.contains(id) {
            let geometry = NotchGeometry.resolve(
                screen.screenDescriptor,
                widthOffset: configuration.widthOffset,
                forcePill: configuration.forcePill
            )
            if let controller = controllers[id] {
                controller.update(geometry: geometry)
            } else {
                let controller = IslandController(
                    displayID: id, geometry: geometry, behavior: behavior,
                    accessibility: accessibility, actions: actions
                )
                controller.setHiddenFromCapture(hideFromScreenCapture)
                controllers[id] = controller
            }
        }
        applyVisibility()
    }

    private func applyVisibility() {
        for controller in controllers.values { controller.setHidden(isPaused) }
    }
}
